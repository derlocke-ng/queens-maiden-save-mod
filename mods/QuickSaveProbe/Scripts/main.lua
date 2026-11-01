-- QuickSaveProbe v4: step-4 reflection probe. Observes only; never calls a game function that changes state.
--   F8       log the player pawn, its location, and the game instance suspend-save state (F5/F9 belong to QDQuickSave)
--   F6       scan loaded UFunctions for save/load-related names; log owner and parameters
--   F7       rescan, then attach logging hooks to new save/quit/title/death-related functions (re-runnable;
--            hooks stay on until restart)
-- Output goes to ue4ss/UE4SS.log.

local TAG = "[QuickSaveProbe] "

local function log(msg)
    print(TAG .. msg .. "\n")
end

local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

---------------------------------------------------------------- F5 / F9

-- Field names come from the CXXHeaderDump of FS_GameInstance_C / FS_SaveSlot_C.
local GI_FIELDS = { "SuspendSaveWaitDuration", "SuspendLoopShouldRun", "SuspendIsBlocked", "SuspendSaveCurrentlyWriting" }
local SLOT_FIELDS = { "ActiveSuspendSlot", "IsSuspendSave", "SuspendPositionIsForcedMidair", "CurrentPlayerHealth",
                      "CurrentPlayerUltraCharge", "SaveLevel" }

local function fieldText(obj, name)
    local v = safe(function() return obj[name] end)
    if type(v) == "userdata" then
        return safe(function() return v:ToString() end) or safe(function() return v:GetFullName() end) or "<userdata>"
    end
    return tostring(v)
end

function describeSuspendState()
    local gi = FindFirstOf("FS_GameInstance_C")
    if gi == nil or not gi:IsValid() then
        log("FS_GameInstance_C: not found")
        return
    end
    local parts = {}
    for _, f in ipairs(GI_FIELDS) do parts[#parts + 1] = f .. "=" .. fieldText(gi, f) end
    log("GI: " .. table.concat(parts, "  "))
    local slot = safe(function() return gi.ActiveSaveSlot end)
    if slot == nil or not slot:IsValid() then
        log("ActiveSaveSlot: none")
        return
    end
    parts = {}
    for _, f in ipairs(SLOT_FIELDS) do parts[#parts + 1] = f .. "=" .. fieldText(slot, f) end
    log("ActiveSaveSlot " .. slot:GetFullName() .. ": " .. table.concat(parts, "  "))
    local sl = safe(function() return slot.SuspendLocation.Translation end)
    if sl then log(string.format("ActiveSaveSlot.SuspendLocation: (%.1f, %.1f, %.1f)", sl.X, sl.Y, sl.Z)) end
    -- InventoryContents (native TMap<UFS_Item*, int32>; the Blueprint `Inventory` map is not the one saved)
    local items = {}
    safe(function()
        slot.InventoryContents:ForEach(function(k, v)
            local name = safe(function() return k:get():GetFName():ToString() end) or "?"
            items[#items + 1] = name .. "=" .. tostring(safe(function() return v:get() end))
        end)
    end)
    table.sort(items)
    log("ActiveSaveSlot.InventoryContents: " .. (#items > 0 and table.concat(items, ", ") or "(empty or unreadable)"))
end

local function describePlayer(key)
    ExecuteInGameThread(function()
        log(key .. " pressed")
        local pc = FindFirstOf("PlayerController")
        if pc == nil or not pc:IsValid() then
            log("PlayerController: not found (main menu or loading?)")
            return
        end
        log("PlayerController: " .. pc:GetFullName())
        local pawn = pc.Pawn
        if pawn == nil or not pawn:IsValid() then
            log("Pawn: none (possessing nothing right now)")
            return
        end
        log("Pawn: " .. pawn:GetFullName())
        local loc = pawn:K2_GetActorLocation()
        log(string.format("Pawn location: (%.1f, %.1f, %.1f)", loc.X, loc.Y, loc.Z))
        -- AFS_PlayerChar_C::Health / CachedHP (CXXHeaderDump)
        log("Pawn live HP: Health=" .. fieldText(pawn, "Health") .. "  CachedHP=" .. fieldText(pawn, "CachedHP"))
        describeSuspendState()
    end)
end

---------------------------------------------------------------- F6

local NAME_PATTERNS = { "save", "load", "suspend", "slot", "checkpoint", "respawn", "restore", "safelocation",
                        "quit", "exit", "title", "death", "died", "level", "volume", "soundmix", "duck", "lowpass" }

-- Hooked in F7: every match under these owners, plus Blueprint (/Game/) functions whose names match
-- the narrower HOOK_PATTERNS ("load"/"slot" alone are too noisy there: UI, animation slots).
-- Everything else F6 finds is only listed.
local HOOK_OWNERS = { "/Script/FB_SaveUtils", "/Script/QueensDomain", "/Game/Blueprints/SaveSystem/",
                      "/Game/Blueprints/FS_GameInstance.", "/Game/UI/Menus/PauseMenu.", "/Game/UI/Title/TitleScreenUI." }
local HOOK_PATTERNS = { "save", "suspend", "checkpoint", "restore", "safelocation", "quit", "death", "died",
                        "volume", "soundmix", "duck", "lowpass" }

-- Every function of these owners is listed and hooked, whatever its name (death screen: effects-volume bug).
local FULL_OWNERS = { "/Game/UI/Menus/DieUI." }

-- Engine functions the game may use to change maps or quit; hooked directly (engine owners are not scanned).
local EXTRA_HOOKS = {
    "/Script/Engine.GameplayStatics:OpenLevel",
    "/Script/Engine.GameplayStatics:OpenLevelBySoftObjectPtr",
    "/Script/Engine.KismetSystemLibrary:QuitGame",
    -- audio state that survives a level load (effects-volume bug after death + reload)
    "/Script/Engine.GameplayStatics:PushSoundMixModifier",
    "/Script/Engine.GameplayStatics:PopSoundMixModifier",
    "/Script/Engine.GameplayStatics:ClearSoundMixModifiers",
    "/Script/Engine.GameplayStatics:SetBaseSoundMix",
    "/Script/Engine.GameplayStatics:SetSoundMixClassOverride",
    "/Script/Engine.GameplayStatics:ClearSoundMixClassOverride",
    "/Script/Engine.GameplayStatics:SetGlobalPitchModulation",
    "/Script/Engine.GameplayStatics:ActivateReverbEffect",
    "/Script/Engine.GameplayStatics:DeactivateReverbEffect",
}

-- Called every frame or thousands of times per minute (trace 1); hooking them only costs frame time.
local HOOK_SKIP = {
    "GetActiveSystemSave", "GetActiveBaseSave", "GetCurrentlyActiveSave", "RetrieveEnemySaveState", "GetSaveGUID",
    "ExecuteUbergraph_Checkpoint", "GetNamedSaveData", "SaveFunctions_C:GetActiveSave", "SystemSaveDelayTick",
    "UpdateSafeLocation", "CacheSafeLocationState", "ExecuteUbergraph_SaveHelper", "ReadNamedSaveData",
}

local found = {}      -- function path -> true (hookable candidates)

local function matchesAny(name, patterns)
    local lower = name:lower()
    if lower:find("__delegatesignature", 1, true) then return false end
    for _, p in ipairs(patterns) do
        if lower:find(p, 1, true) then return true end
    end
    return false
end

local function isFullOwner(path)
    for _, owner in ipairs(FULL_OWNERS) do
        if path:find(owner, 1, true) == 1 then return true end
    end
    return false
end

local function isHookCandidate(path, name)
    if isFullOwner(path) then return true end
    for _, s in ipairs(HOOK_SKIP) do
        if path:find(s, 1, true) then return false end
    end
    for _, owner in ipairs(HOOK_OWNERS) do
        if path:find(owner, 1, true) == 1 then return true end
    end
    return path:find("/Game/", 1, true) == 1 and matchesAny(name, HOOK_PATTERNS)
end

local function isEngineOwner(path)
    return path:find("^/Script/") ~= nil
        and not path:find("^/Script/FB_")
        and not path:find("^/Script/QueensDomain")
end

local function paramList(func)
    local parts = {}
    safe(function()
        func:ForEachProperty(function(prop)
            local pname = prop:GetFName():ToString()
            local ptype = safe(function() return prop:GetClass():GetFName():ToString() end) or "?"
            parts[#parts + 1] = ptype .. " " .. pname
        end)
    end)
    return table.concat(parts, ", ")
end

-- Must run on the game thread.
local function doScan()
    log("F6: scanning loaded functions (the game may pause for a few seconds)")
    local FunctionName = FName("Function")
    local count, listed = 0, 0
    ForEachUObject(function(obj)
        count = count + 1
        local cls = obj:GetClass()
        if not cls:IsValid() or cls:GetFName() ~= FunctionName then return end
        local name = obj:GetFName():ToString()
        local full = obj:GetFullName()                 -- "Function /Path/Owner.Class:Func"
        local path = full:match("^%S+%s+(.+)$") or full
        if not matchesAny(name, NAME_PATTERNS) and not isFullOwner(path) then return end
        if isEngineOwner(path) then return end
        listed = listed + 1
        local hook = isHookCandidate(path, name)
        log((hook and "FN* " or "FN  ") .. path .. "(" .. paramList(obj) .. ")")
        if hook then found[path] = true end
    end)
    local n = 0
    for _ in pairs(found) do n = n + 1 end
    log(string.format("F6: done; %d objects visited, %d functions listed, %d hook candidates", count, listed, n))
end

local function scanFunctions()
    ExecuteInGameThread(doScan)
end

---------------------------------------------------------------- F7

local hookedPaths = {}   -- path -> true once a hook was attempted
local callCounts = {}

local function describeValue(param)
    local v = safe(function() return param:get() end)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return '"' .. v .. '"' end
    if v == nil then return "nil" end
    local s = safe(function() return v:GetFullName() end)
    if s then return s end
    s = safe(function() return v:ToString() end)
    if s then return '"' .. s .. '"' end
    return "<" .. t .. ">"
end

local function makeLogger(path)
    return function(self, ...)
        local c = (callCounts[path] or 0) + 1
        callCounts[path] = c
        -- Rate-limit chatty functions: first 30 calls, then every 500th.
        if c > 30 and c % 500 ~= 0 then return end
        local args = {}
        for i, p in ipairs({ ... }) do args[i] = describeValue(p) end
        local ctx = safe(function() return self:get():GetFullName() end) or "?"
        log(string.format("CALL #%d %s  self=%s  args=(%s)", c, path, ctx, table.concat(args, ", ")))
    end
end

-- Re-runnable: each press rescans (classes loaded later, e.g. the title screen, become visible) and hooks only new paths.
local function hookAll()
    ExecuteInGameThread(function()
        doScan()
        local candidates = {}
        for path in pairs(found) do candidates[#candidates + 1] = path end
        for _, path in ipairs(EXTRA_HOOKS) do
            local fn = StaticFindObject(path)
            if fn and fn:IsValid() then candidates[#candidates + 1] = path end
        end
        local ok, failed, total = 0, 0, 0
        for _, path in ipairs(candidates) do
            if not hookedPaths[path] then
                hookedPaths[path] = true
                local good = pcall(RegisterHook, path, makeLogger(path))
                if good then ok = ok + 1 else failed = failed + 1; log("F7: could not hook " .. path) end
            end
        end
        for _ in pairs(hookedPaths) do total = total + 1 end
        log(string.format("F7: %d new hooks, %d failed, %d paths hooked in total. Calls appear as CALL lines", ok, failed, total))
    end)
end

RegisterKeyBind(Key.F8, function() describePlayer("F8") end)
RegisterKeyBind(Key.F6, scanFunctions)
RegisterKeyBind(Key.F7, hookAll)

log("v4 loaded; F8 player/suspend info, F6 scan save functions, F7 (re)hook them")
