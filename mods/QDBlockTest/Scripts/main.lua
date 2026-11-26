-- QDBlockTest: test tool for QDQuickSave's boss arena fix. Not shipped.
--
-- Boss arenas call FS_GameInstance_C:BlockSuspendSaves on entry and UnBlockSuspendSaves on exit. Dying or quitting
-- inside one skips the exit call, and the counter (FS_GameInstance_C.SuspendIsBlocked) stays raised until the game
-- is closed. These keys make the same calls anywhere, so the stuck state can be tested without reaching a boss:
--   Ctrl+F10  BlockSuspendSaves      (like entering a boss arena)
--   Ctrl+F11  UnBlockSuspendSaves    (like leaving it)
--   Ctrl+F12  log the counter
-- Every key logs "[QDBlockTest] SuspendIsBlocked a -> b" to ue4ss/UE4SS.log. Restarting the game resets the counter.

local TAG = "[QDBlockTest] "

local function log(msg) print(TAG .. msg .. "\n") end

local function gameInstance()
    local gi = FindFirstOf("FS_GameInstance_C")
    if gi == nil or not gi:IsValid() then return nil end
    return gi
end

local function counter(gi)
    local ok, v = pcall(function() return gi.SuspendIsBlocked end)
    return ok and v or nil
end

local function call(fnName)
    return function()
        ExecuteInGameThread(function()
            local gi = gameInstance()
            if not gi then log(fnName .. ": game instance not found") return end
            local before = counter(gi)
            if fnName then
                local ok, err = pcall(function() gi[fnName](gi) end)
                if not ok then log(fnName .. " failed: " .. tostring(err)) return end
            end
            log(string.format("%s: SuspendIsBlocked %s -> %s", fnName or "status", tostring(before), tostring(counter(gi))))
        end)
    end
end

RegisterKeyBind(Key.F10, { ModifierKey.CONTROL }, call("BlockSuspendSaves"))
RegisterKeyBind(Key.F11, { ModifierKey.CONTROL }, call("UnBlockSuspendSaves"))
RegisterKeyBind(Key.F12, { ModifierKey.CONTROL }, call(nil))
log("loaded: Ctrl+F10 block, Ctrl+F11 unblock, Ctrl+F12 status")
