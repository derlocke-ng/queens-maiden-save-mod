-- QDQuickSave for Queens Domain (UE 4.27, UE4SS experimental).
--
-- Built on the game's own hidden suspend save (written every 120 s and resumed when the slot is loaded):
--   F5 (in game)       Only once the slot has a Crystal Monument save. Ask the game to write its suspend save now
--                      (FS_GameInstance_C:GI_WriteSuspendSaveImmediately), wait until one of the slot's two suspend
--                      files has new, stable bytes, then copy it to QuickSave_World<N>.sav (the game never reads or
--                      deletes that name).
--   F9 (in game,       Press twice within 3 s. Stops the game's suspend loop, copies QuickSave_World<N>.sav into
--      also on the     World<N>_Suspend_0/1.sav, then makes the two calls the title screen makes when a slot is chosen:
--      death screen)   FS_GameInstance_C:ForceLoadNewSlot(false, 0) and GameplayStatics:OpenLevel(SaveLevel).
--                      The game then resumes the suspend save as usual.
--   F9 (title screen)  With slot N highlighted in the Play list: copy the quicksave into that slot's suspend files;
--                      selecting the slot then loads it.
--
-- On-screen messages: a CommonTextBlock in the game's DefaultTextStyle in a mod-owned widget above all game screens;
-- they are also written to ue4ss/UE4SS.log. Never writes World<N>.sav, World<N>_backup.sav, System*, or Challenges*.

local TAG = "[QDQuickSave] "

local GI_CLASS = "FS_GameInstance_C"
local POLL_MS = 250
local SAVE_TIMEOUT_MS = 20000
local CONFIRM_MS = 3000
local DEATH_DUCK_MIX = "/Game/Audio/MixControls/DeathSoundsDuck.DeathSoundsDuck"
local TOAST_MS = 2500
local DEATH_HINT_MS = 8000

local function log(msg)
    print(TAG .. msg .. "\n")
end

local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local function str(v)
    if type(v) == "string" then return v end
    return safe(function() return v:ToString() end)
end

---------------------------------------------------------------- files

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("a")
    f:close()
    return data
end

local function isGvas(data)
    return data ~= nil and #data > 4 and data:sub(1, 4) == "GVAS"
end

-- Write data to dst via dst.tmp. With keepPrev, an existing dst is rotated to dst.prev.
-- Returns true, or false and a reason.
local function writeFileSafely(dst, data, keepPrev)
    local tmp = dst .. ".tmp"
    local o = io.open(tmp, "wb")
    if not o then return false, "cannot write " .. tmp end
    o:write(data)
    o:close()
    if readFile(tmp) ~= data then
        os.remove(tmp)
        return false, "verification of " .. tmp .. " failed"
    end
    -- rename() on Windows does not replace an existing target, so clear the target first.
    if readFile(dst) ~= nil then
        if keepPrev then
            os.remove(dst .. ".prev")
            local ok, err = os.rename(dst, dst .. ".prev")
            if not ok then os.remove(tmp); return false, "cannot rotate " .. dst .. ": " .. tostring(err) end
        else
            local ok, err = os.remove(dst)
            if not ok then os.remove(tmp); return false, "cannot replace " .. dst .. ": " .. tostring(err) end
        end
    end
    local ok, err = os.rename(tmp, dst)
    if not ok then return false, "cannot rename " .. tmp .. ": " .. tostring(err) end
    return true
end

---------------------------------------------------------------- game queries (game thread only)

local function getGameInstance()
    local gi = FindFirstOf(GI_CLASS)
    if gi == nil or not gi:IsValid() then return nil end
    return gi
end

local function getPlayerController()
    local pc = FindFirstOf("PlayerController")
    if pc == nil or not pc:IsValid() then return nil end
    return pc
end

local function getPawn()
    local pc = getPlayerController()
    if not pc then return nil end
    local pawn = safe(function() return pc.Pawn end)
    if pawn == nil or not pawn:IsValid() then return nil end
    return pawn
end

-- True when an instance of className is actually on screen. Some game menus stay in the viewport after closing,
-- only hidden or faded out (v9 test: F5 kept saying "close the menu first" after leaving a monolith), so being
-- in the viewport alone is not enough.
local function anyInViewport(className)
    for _, w in ipairs(FindAllOf(className) or {}) do
        if w:IsValid()
            and safe(function() return w:IsInViewport() end) == true
            and safe(function() return w:IsVisible() end) == true
            and (safe(function() return w:GetRenderOpacity() end) or 1) > 0.01 then
            return true
        end
    end
    return false
end

local function onTitleScreen() return anyInViewport("TitleScreenUI_C") end
local function onDeathScreen() return anyInViewport("DieUI_C") end

local function isPaused(worldContext)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    return gs ~= nil and gs:IsValid() and safe(function() return gs:IsGamePaused(worldContext) end) == true
end

---------------------------------------------------------------- death duck
--
-- About a second after the death animation starts the game pushes the DeathSoundsDuck sound mix (quieter effects);
-- its own Continue pops it before reloading. Sound mix modifiers live in the audio device and survive OpenLevel, so a
-- quickload made while it is pushed kept the effects quieter until a restart (QDAudioTrace, v1.0.1).
-- Popping a mix that is not pushed does nothing, so it is simply popped whenever a death may have pushed it.
-- (v1.0.2 counted pushes with native hooks on GameplayStatics:Push/PopSoundMixModifier; UE4SS could not resolve some
-- calls through those hooks and the game crashed when opening the video options. No native hooks any more.)

local function popDeathDuck(gi)
    local mix = StaticFindObject(DEATH_DUCK_MIX)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local popped = mix ~= nil and mix:IsValid() and gs ~= nil and gs:IsValid()
        and pcall(function() gs:PopSoundMixModifier(gi, mix) end)
    log("PopSoundMixModifier(DeathSoundsDuck) " .. (popped and "done" or "not possible"))
end

local function validSlot(n)
    if type(n) == "number" and n >= 0 and n <= 9 then return math.floor(n) end
    return nil
end

-- FS_GameInstance_C:GetActiveSaveSlotIndex (Blueprint), falling back to the native FB_SaveSubsystem.
-- Correct in game once a slot is loaded; reads 0 on the title screen after a fresh launch (test T2).
local function activeSlotIndex(gi)
    local n = validSlot(safe(function() return gi:GetActiveSaveSlotIndex() end))
    if n then return n end
    local sub = FindFirstOf("FB_SaveSubsystem")
    if sub ~= nil and sub:IsValid() then
        return validSlot(safe(function() return sub:GetCurrentSaveFileSlot() end))
    end
    return nil
end

-- Windows path of World<N>_Suspend_<k>.sav, from the game's own BlueprintUtils:GetSaveSlotName.
local function suspendPath(slot, k)
    local utils = StaticFindObject("/Script/QueensDomain.Default__BlueprintUtils")
    if utils == nil or not utils:IsValid() then return nil end
    local name = str(safe(function() return utils:GetSaveSlotName(slot, false, false, true, k) end))
    if not name then return nil end
    local path = name:gsub("^FULLPATH:", "")
    if not path:match("World" .. slot .. "_Suspend_" .. k .. "%.sav$") then
        log("unexpected suspend slot name: " .. name)
        return nil
    end
    return path
end

local function siblingPath(slot, fileName)
    local p = suspendPath(slot, 0)
    if not p then return nil end
    return (p:gsub("World%d+_Suspend_%d+%.sav$", fileName))
end

local function quickSavePath(slot) return siblingPath(slot, "QuickSave_World" .. slot .. ".sav") end

-- The title treats a slot without World<N>.sav as empty and starts a new game, discarding armed suspend files
-- (test T9), so quicksaving and quickloading require a regular (monolith) save in the slot.
local function hasWorldSave(slot)
    local p = siblingPath(slot, "World" .. slot .. ".sav")
    return p ~= nil and isGvas(readFile(p))
end

-- Returns the quicksave bytes for slot, or nil and a short reason.
local function loadableQuickSave(slot)
    local src = quickSavePath(slot)
    local data = src and readFile(src)
    if not isGvas(data) then return nil, "no quicksave for this slot" end
    if not data:find("IsSuspendSave", 1, true) then return nil, "quicksave file is not a suspend save" end
    if not hasWorldSave(slot) then return nil, "save at a Crystal Monument in this slot first" end
    return data
end

-- Copy the quicksave into both suspend files of slot, so whichever the game picks is the quicksave.
local function armSuspendFiles(slot, data)
    for k = 0, 1 do
        local dst = suspendPath(slot, k)
        if not dst then return false, "no suspend path for index " .. k end
        local ok, err = writeFileSafely(dst, data, false)
        if not ok then return false, err end
    end
    return true
end

---------------------------------------------------------------- on-screen messages

-- One mod-owned widget at viewport z-order 10000, above every game screen (HUD, menus, death screen, title).
-- UE 4.27 cannot instantiate UUserWidget itself, so an instance of a tiny game widget (CreditLinkText_C: only a
-- PreConstruct and click handlers for its own button) is created and its root is replaced with a mod CanvasPanel
-- holding a CommonTextBlock in the game's DefaultTextStyle, before the widget is first shown.
-- History: v5 reused MenuButtonHintWidget_C (hides itself without an input binding); v6/v7 placed text inside game
-- widgets, which stayed hidden behind sub-menus such as Status & Inventory and the Bestiary (user test).
local CONTAINER_ASSET = "/Game/UI/Title/CreditLinkText"
local CONTAINER_CLASS = "/Game/UI/Title/CreditLinkText.CreditLinkText_C"
local TEXT_STYLE_CLASS = "/Game/UI/UI_Style/FontStyles/DefaultTextStyle.DefaultTextStyle_C"
local OVERLAY_ZORDER = 10000
local MESSAGE_ANCHOR_Y = 0.12      -- 12 % from the top of the screen (user feedback)
local ESLATE_COLLAPSED = 1
local ESLATE_HIT_TEST_INVISIBLE = 3
local ETEXT_JUSTIFY_CENTER = 1

local overlay = nil              -- { widget = UUserWidget, text = UCommonTextBlock, ownerAddr = number }
local toastGeneration = 0
local toastFailures = 0
local toastBroken = false

local function findClass(path, asset)
    local cls = StaticFindObject(path)
    if (cls == nil or not cls:IsValid()) and asset then
        safe(function() LoadAsset(asset) end)
        cls = StaticFindObject(path)
    end
    if cls == nil or not cls:IsValid() then return nil end
    return cls
end

-- Recreated whenever the PlayerController changes (every level load), so a widget owned by a destroyed
-- controller is never re-added to the viewport.
local function ensureOverlay(pc)
    local pcAddr = safe(function() return pc:GetAddress() end)
    if overlay and overlay.widget:IsValid() and overlay.text:IsValid() and overlay.ownerAddr == pcAddr then
        return overlay
    end
    if overlay and overlay.widget:IsValid() then safe(function() overlay.widget:RemoveFromParent() end) end
    overlay = nil
    local container = findClass(CONTAINER_CLASS, CONTAINER_ASSET)
    local canvasCls = findClass("/Script/UMG.CanvasPanel")
    local textCls = findClass("/Script/CommonUI.CommonTextBlock")
    local lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not (container and canvasCls and textCls) or lib == nil or not lib:IsValid() then
        error("widget classes not available")
    end
    local w = lib:Create(pc, container, pc)
    if w == nil or not w:IsValid() then error("could not create the message widget") end
    local tree = w.WidgetTree
    local canvas = StaticConstructObject(canvasCls, tree)
    local text = StaticConstructObject(textCls, tree)
    local style = findClass(TEXT_STYLE_CLASS)
    if style then safe(function() text:SetStyle(style) end) end
    safe(function() text:SetJustification(ETEXT_JUSTIFY_CENTER) end)
    local slot = canvas:AddChildToCanvas(text)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = MESSAGE_ANCHOR_Y }, Maximum = { X = 0.5, Y = MESSAGE_ANCHOR_Y } })
    slot:SetAlignment({ X = 0.5, Y = 0.5 })
    slot:SetAutoSize(true)
    tree.RootWidget = canvas
    -- Never take mouse clicks or focus away from the game.
    w:SetVisibility(ESLATE_HIT_TEST_INVISIBLE)
    overlay = { widget = w, text = text, ownerAddr = pcAddr }
    return overlay
end

-- Must run on the game thread. Always logs; shows the text on screen when possible.
local function showMessage(message, ms)
    log("MESSAGE: " .. message)
    if toastBroken then return end
    local ok, err = pcall(function()
        local pc = getPlayerController()
        if not pc then error("no player controller") end
        local o = ensureOverlay(pc)
        if not o.widget:IsInViewport() then o.widget:AddToViewport(OVERLAY_ZORDER) end
        o.text:SetText(FText(message))
        o.text:SetVisibility(ESLATE_HIT_TEST_INVISIBLE)
    end)
    if not ok then
        toastFailures = toastFailures + 1
        log("on-screen message failed: " .. tostring(err))
        if toastFailures >= 5 then toastBroken = true; log("on-screen messages disabled; log only from now on") end
        return
    end
    toastGeneration = toastGeneration + 1
    local gen = toastGeneration
    ExecuteWithDelay(ms or TOAST_MS, function()
        ExecuteInGameThread(function()
            if gen == toastGeneration and overlay and overlay.text:IsValid() then
                safe(function() overlay.text:SetVisibility(ESLATE_COLLAPSED) end)
            end
        end)
    end)
end

---------------------------------------------------------------- unsupported game states

-- Game screens that do not pause the game, so IsGamePaused alone does not catch them (v8 test: F5 was accepted
-- at a monolith). The monolith interaction itself is tracked from FS_PlayerChar_C:OpenSaveMenu to ClosedSaveMenu,
-- which also covers the rest animation before the menu appears.
local NON_PAUSING_MENUS = { "SaveMenu_C", "SaveTeleportUI_C", "ShopMenu_C", "KeyUseMenu_C", "GameplayModalMenu_C",
                            "DialogueScreen_C" }
local monolithPawnAddr = nil     -- set while that pawn is in a monolith interaction
local monolithSince = 0
local MONOLITH_STALE_S = 20      -- ignore the flag after this long without a save/teleport menu on screen,
                                 -- in case the game ever skips ClosedSaveMenu

local function onOpenSaveMenu(self)
    monolithPawnAddr = safe(function() return self:get():GetAddress() end)
    monolithSince = os.time()
end

local function onClosedSaveMenu(self)
    monolithPawnAddr = nil
end

-- FS_PlayerChar_C:DeathAnim starts the death animation, seconds before the death screen; the reload spawns a new pawn.
local dyingPawnAddr = nil

local function onDeathAnim(self)
    dyingPawnAddr = safe(function() return self:get():GetAddress() end)
end

local function isDying(pawn)
    return dyingPawnAddr ~= nil and pawn ~= nil and safe(function() return pawn:GetAddress() end) == dyingPawnAddr
end

-- Returns a short reason when the player is in a monolith interaction or a non-pausing menu, else nil.
local function busyReason(pawn)
    if monolithPawnAddr ~= nil and pawn and safe(function() return pawn:GetAddress() end) == monolithPawnAddr then
        local menuOpen = anyInViewport("SaveMenu_C") or anyInViewport("SaveTeleportUI_C")
        if menuOpen or os.time() - monolithSince < MONOLITH_STALE_S then return "not while at a Crystal Monument" end
        monolithPawnAddr = nil
    end
    for _, cls in ipairs(NON_PAUSING_MENUS) do
        if anyInViewport(cls) then
            log("blocked by visible menu " .. cls)
            return "close the menu first"
        end
    end
    return nil
end

---------------------------------------------------------------- F5 quicksave

local saving = false
local requestCounter = 0

-- Returns gi, slot on success; nil, short reason when quicksaving is not supported right now.
local function checkCanQuickSave()
    local gi = getGameInstance()
    if not gi then return nil, "game not ready" end
    if onTitleScreen() then return nil, "load a slot first" end
    local save = safe(function() return gi.ActiveSaveSlot end)
    if save == nil or not save:IsValid() then return nil, "no active save" end
    local pawn = getPawn()
    if not pawn then return nil, "not in game" end
    if onDeathScreen() or isDying(pawn) then return nil, "not while dead" end
    if safe(function() return gi.InCutscene end) == true then return nil, "not during a cutscene" end
    if isPaused(pawn) then return nil, "close the menu first" end
    local busy = busyReason(pawn)
    if busy then return nil, busy end
    -- The game's own block counter. Observed values: 0, -1, -3; only positive values are treated as blocked.
    local blocked = safe(function() return gi.SuspendIsBlocked end) or 0
    if blocked > 0 then return nil, "the game blocks saving here" end
    if safe(function() return gi.SuspendSaveCurrentlyWriting end) == true then return nil, "game is saving, try again" end
    if saving then return nil, "quicksave already in progress" end
    local slot = activeSlotIndex(gi)
    if not slot then return nil, "cannot determine the save slot" end
    if not hasWorldSave(slot) then return nil, "save at a Crystal Monument in this slot first" end
    return gi, slot
end

-- Find the suspend file the game rewrote since `before` was taken. Prefers the index the game marks as
-- written (ActiveSuspendSlot); falls back to whichever of the two files changed.
local function changedSuspendFile(gi, slot, before)
    local save = safe(function() return gi.ActiveSaveSlot end)
    local marked = save and safe(function() return save.ActiveSuspendSlot end)
    local order = (marked == 1) and { 1, 0 } or { 0, 1 }
    for _, k in ipairs(order) do
        local src = suspendPath(slot, k)
        local data = src and readFile(src)
        if isGvas(data) and data ~= before[k] then return src, data end
    end
    return nil
end

local function finishQuickSave(id, slot, before, waited)
    ExecuteInGameThread(function()
        local gi = getGameInstance()
        local writing = gi == nil or safe(function() return gi.SuspendSaveCurrentlyWriting end) == true
        local src, data = nil, nil
        if not writing then src, data = changedSuspendFile(gi, slot, before) end
        if not src then
            if waited >= SAVE_TIMEOUT_MS then
                saving = false
                log(string.format("QUICKSAVE #%d FAILED: no suspend file of slot %d changed within %d s",
                    id, slot, SAVE_TIMEOUT_MS // 1000))
                showMessage("Quicksave failed")
                return
            end
            ExecuteWithDelay(POLL_MS, function() finishQuickSave(id, slot, before, waited + POLL_MS) end)
            return
        end
        -- Read twice, one poll apart, so a file still being written is not copied.
        ExecuteWithDelay(POLL_MS, function()
            ExecuteInGameThread(function()
                local again = readFile(src)
                if again ~= data then
                    finishQuickSave(id, slot, before, waited + POLL_MS)
                    return
                end
                saving = false
                local dst = quickSavePath(slot)
                local ok, err = false, "no quicksave path"
                if dst then ok, err = writeFileSafely(dst, data, true) end
                if ok then
                    log(string.format("QUICKSAVE #%d OK: slot %d (title slot %d), from %s, %d bytes -> %s",
                        id, slot, slot + 1, src:match("[^/\\]+$"), #data, dst))
                    showMessage(string.format("Quicksave saved - Slot %d", slot + 1))
                else
                    log(string.format("QUICKSAVE #%d FAILED while copying: %s", id, err))
                    showMessage("Quicksave failed")
                end
            end)
        end)
    end)
end

local function quickSave()
    ExecuteInGameThread(function()
        local gi, slotOrWhy = checkCanQuickSave()
        if not gi then
            log("QUICKSAVE refused: " .. slotOrWhy)
            showMessage("Can't quicksave: " .. slotOrWhy)
            return
        end
        local slot = slotOrWhy
        -- Remember both suspend files so the one the game rewrites can be recognised.
        local before = { [0] = readFile(suspendPath(slot, 0) or ""), [1] = readFile(suspendPath(slot, 1) or "") }
        requestCounter = requestCounter + 1
        local id = requestCounter
        saving = true
        log(string.format("QUICKSAVE #%d requested for slot %d (GI_WriteSuspendSaveImmediately)", id, slot))
        if not pcall(function() gi:GI_WriteSuspendSaveImmediately(false) end) then
            saving = false
            log(string.format("QUICKSAVE #%d FAILED: could not call GI_WriteSuspendSaveImmediately", id))
            showMessage("Quicksave failed")
            return
        end
        finishQuickSave(id, slot, before, 0)
    end)
end

---------------------------------------------------------------- Blueprint hooks (title slot list, death screen)

-- TitleScreenUI_C:SaveSlotFocused(Index) fires whenever a slot is highlighted in the Play list (same 0-based index as
-- SaveSlotSelected). DieUI_C:ShowButtons runs when the death screen offers its buttons.
local focusedSlot = nil
local loadPending = false
local pendingLoadedSlot = nil   -- slot whose quicksave was armed; confirmed by FS_PlayerChar_C:RestoreSuspend

local function onSlotFocused(self, index)
    focusedSlot = validSlot(safe(function() return index:get() end))
end

local function onSlotSelected(self, index)
    focusedSlot = nil    -- a load started; require a fresh highlight on the next title visit
end

-- FS_PlayerChar_C:RestoreSuspend runs once the game has placed the player at the suspend position (traces v6).
local function onRestoreSuspend(self)
    local slot = pendingLoadedSlot
    if slot == nil then return end
    local gi = getGameInstance()
    if not gi or activeSlotIndex(gi) ~= slot then return end
    pendingLoadedSlot = nil
    ExecuteWithDelay(1500, function()
        ExecuteInGameThread(function() showMessage(string.format("Quicksave loaded - Slot %d", slot + 1)) end)
    end)
end

-- FS_PlayerChar_C:RestoreToSavePoint runs when any load (game's or ours) has finished. After a death, pop the duck once
-- more: a quickload in the first second of the death animation runs before the game pushes it.
local function onRestoreToSavePoint(self)
    local diedBefore = dyingPawnAddr ~= nil
    dyingPawnAddr = nil   -- a new pawn may reuse the old one's address
    local gi = getGameInstance()
    if gi and diedBefore then popDeathDuck(gi) end
end

local function onDeathButtons(self)
    if loadPending then return end
    local gi = getGameInstance()
    local slot = gi and activeSlotIndex(gi)
    if slot and loadableQuickSave(slot) then
        showMessage("F9 (twice): continue from quicksave", DEATH_HINT_MS)
    end
end

-- These classes are loaded on demand and may be reloaded later, so re-check every 2 s and hook each new
-- UFunction object once (a partial failure cannot stack duplicate hooks).
local BP_HOOKS = {
    { path = "/Game/UI/Title/TitleScreenUI.TitleScreenUI_C:SaveSlotFocused", fn = onSlotFocused },
    { path = "/Game/UI/Title/TitleScreenUI.TitleScreenUI_C:SaveSlotSelected", fn = onSlotSelected },
    { path = "/Game/UI/Menus/DieUI.DieUI_C:ShowButtons", fn = onDeathButtons },
    { path = "/Game/Player/FS_PlayerChar.FS_PlayerChar_C:RestoreSuspend", fn = onRestoreSuspend },
    { path = "/Game/Player/FS_PlayerChar.FS_PlayerChar_C:OpenSaveMenu", fn = onOpenSaveMenu },
    { path = "/Game/Player/FS_PlayerChar.FS_PlayerChar_C:ClosedSaveMenu", fn = onClosedSaveMenu },
    { path = "/Game/Player/FS_PlayerChar.FS_PlayerChar_C:DeathAnim", fn = onDeathAnim },
    { path = "/Game/Player/FS_PlayerChar.FS_PlayerChar_C:RestoreToSavePoint", fn = onRestoreToSavePoint },
}

local function maintainHooks()
    ExecuteInGameThread(function()
        for _, h in ipairs(BP_HOOKS) do
            local f = StaticFindObject(h.path)
            local addr = f and f:IsValid() and safe(function() return f:GetAddress() end)
            if addr and addr ~= h.addr then
                h.addr = addr
                if h.fn == onSlotFocused then focusedSlot = nil end
                if not pcall(RegisterHook, h.path, h.fn) and not h.failureLogged then
                    h.failureLogged = true
                    log("could not hook " .. h.path)
                end
            end
        end
    end)
    ExecuteWithDelay(2000, maintainHooks)
end

---------------------------------------------------------------- F9 quickload

local confirmToken = nil

local function quickLoadOnTitle(gi)
    local slot = focusedSlot
    if not slot then
        showMessage("Choose Play and highlight a slot, then press F9")
        return
    end
    local data, why = loadableQuickSave(slot)
    if not data then
        log(string.format("QUICKLOAD refused for slot %d: %s", slot, why))
        showMessage(string.format("Slot %d: %s", slot + 1, why))
        return
    end
    local ok, err = armSuspendFiles(slot, data)
    if not ok then
        log("QUICKLOAD FAILED: " .. err)
        showMessage("Quickload failed")
        return
    end
    pendingLoadedSlot = slot
    log(string.format("QUICKLOAD armed on title: slot %d (title slot %d)", slot, slot + 1))
    showMessage(string.format("Quicksave ready - select Slot %d to load it", slot + 1), 4000)
end

local function quickLoadInGame(gi)
    local pawn = getPawn()
    local dead = onDeathScreen()
    if not pawn and not dead then showMessage("Can't quickload: not in game") return end
    if not dead then
        if safe(function() return gi.InCutscene end) == true then showMessage("Can't quickload: not during a cutscene") return end
        if pawn and isPaused(pawn) then showMessage("Can't quickload: close the menu first") return end
        local busy = busyReason(pawn)
        if busy then showMessage("Can't quickload: " .. busy) return end
    end
    if loadPending then return end
    if saving then showMessage("Can't quickload: quicksave in progress") return end
    if safe(function() return gi.SuspendSaveCurrentlyWriting end) == true then
        showMessage("Can't quickload: game is saving, try again")
        return
    end
    local slot = activeSlotIndex(gi)
    if not slot then showMessage("Can't quickload: cannot determine the save slot") return end
    local data, why = loadableQuickSave(slot)
    if not data then
        log(string.format("QUICKLOAD refused for slot %d: %s", slot, why))
        showMessage("Can't quickload: " .. why)
        return
    end

    -- First press only asks for confirmation; the second press within CONFIRM_MS loads.
    if confirmToken == nil then
        local token = {}
        confirmToken = token
        showMessage("Press F9 again to load quicksave", CONFIRM_MS)
        ExecuteWithDelay(CONFIRM_MS, function() if confirmToken == token then confirmToken = nil end end)
        return
    end
    confirmToken = nil

    -- Keep the game's 120 s suspend loop from overwriting the armed files before the reload reads them.
    safe(function() gi:CancelSuspendSaveLoop() end)
    local ok, err = armSuspendFiles(slot, data)
    if not ok then
        safe(function() gi:StartSuspendSaveLoop() end)
        log("QUICKLOAD FAILED: " .. err)
        showMessage("Quickload failed")
        return
    end
    loadPending = true
    local dying = not dead and isDying(pawn)
    log(string.format("QUICKLOAD in game: slot %d armed%s", slot,
        dead and " (death screen)" or dying and " (death animation)" or ""))
    pendingLoadedSlot = slot
    -- Like the game's own Continue, remove the death duck before reloading.
    if dead or dying then popDeathDuck(gi) end
    -- The same two calls the title screen makes when a slot is selected (observed with a logging probe):
    --   FS_GameInstance_C:ForceLoadNewSlot(false, 0)  loads the active slot from disk (suspend files preferred) and
    --                                                 makes it the active save;
    --   GameplayStatics:OpenLevel(ctx, SaveLevel, true, "")  starts the level load.
    -- (v5 used Load Game(false); it returned without doing anything.)
    local loaded = pcall(function() gi:ForceLoadNewSlot(false, 0) end)
    local save = loaded and safe(function() return gi.ActiveSaveSlot end)
    local isSuspend = save and safe(function() return save.IsSuspendSave end)
    local level = save and str(safe(function() return save.SaveLevel end))
    if not loaded or not level or level == "" or level == "None" then
        loadPending = false
        pendingLoadedSlot = nil
        -- Undo: remove the armed files (the game's own deletion) and restart its loop. If ForceLoadNewSlot did run,
        -- the active save object now holds the disk state while the world does not; the log says so.
        safe(function() gi:GI_DeleteSuspendSaves(false, true) end)
        safe(function() gi:StartSuspendSaveLoop() end)
        log(string.format("QUICKLOAD FAILED: ForceLoadNewSlot %s, SaveLevel=%s", loaded and "ran" or "could not be called",
            tostring(level)))
        showMessage(loaded and "Quickload failed - quit to title and reload the slot" or "Quickload failed")
        return
    end
    log(string.format("QUICKLOAD: active save IsSuspendSave=%s, opening level %s", tostring(isSuspend), level))
    if isSuspend ~= true then
        pendingLoadedSlot = nil
        log("QUICKLOAD WARNING: the game did not pick the armed suspend file; the level loads from the monolith save")
    end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local opened = gs ~= nil and gs:IsValid() and pcall(function() gs:OpenLevel(gi, FName(level), true, "") end)
    if not opened then
        loadPending = false
        pendingLoadedSlot = nil
        log("QUICKLOAD FAILED: OpenLevel could not be called")
        showMessage("Quickload failed - quit to title and reload the slot")
        return
    end
    -- The reload replaces the world; clear the flag once it has had time to start.
    ExecuteWithDelay(10000, function() loadPending = false end)
end

local function quickLoad()
    ExecuteInGameThread(function()
        local gi = getGameInstance()
        if not gi then log("QUICKLOAD refused: game instance not found") return end
        if onTitleScreen() then quickLoadOnTitle(gi) else quickLoadInGame(gi) end
    end)
end

RegisterKeyBind(Key.F5, quickSave)
RegisterKeyBind(Key.F9, quickLoad)
maintainHooks()

-- Release builds add VERSION.txt next to Scripts/. Find it relative to this script (the process working directory is
-- not the ue4ss folder: v1.0.0 always logged "dev"), with relative paths as fallbacks.
local function readVersion()
    local candidates = {}
    local src = safe(function() return debug.getinfo(1, "S").source end) or ""
    local dir = src:gsub("^@", ""):match("^(.*[/\\])Scripts[/\\]main%.lua$")
    if dir then candidates[#candidates + 1] = dir .. "VERSION.txt" end
    candidates[#candidates + 1] = "Mods/QDQuickSave/VERSION.txt"
    candidates[#candidates + 1] = "ue4ss/Mods/QDQuickSave/VERSION.txt"
    for _, path in ipairs(candidates) do
        local v = (readFile(path) or ""):match("QDQuickSave%s+(%S+)")
        if v then return v end
    end
    return "dev"
end
local releaseVersion = readVersion()
log("QDQuickSave " .. releaseVersion .. " loaded: F5 quicksave, F9 (twice) quickload in game or on the death screen,"
    .. " F9 on the title for the highlighted slot")
