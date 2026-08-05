-- grade_probe.lua -- DEV PROBE for the mounted-aggro / BiologicalGrade plan. TEMPORARY: delete + drop
-- the require before any release. Touches ONLY the player (a stable, long-lived actor) -- no wild-pal
-- AI -- so it's crash-safe. Everything is pcall/isValid guarded.
--
-- WHAT WE'RE ANSWERING (see the whole plan in STATUS/NEXT):
--   1. The player's BiologicalGrade on FOOT vs MOUNTED (does mounting raise it, and to what?).
--   2. Can we WRITE the player's grade, and does it STICK, or does the game re-apply it every tick?
--   3. With grade pinned to 0: do wild Warlike Pals now engage you (mounted + skittish)? -> behavioural.
-- The flee-from-greater AI compares BiologicalGrade (EPalBiologicalGradeComparedResult); there is no
-- live per-instance Size field to override (Size is a static DB property), so grade is the only lever.
--
-- USE: watch UE4SS.log for [PDST-Probe] lines. On load it prints your foot grade; mount up and it
-- prints the mounted grade. Press F6 to TOGGLE a forced grade of 0 (it re-pins every tick, and logs
-- if the game keeps overwriting it) -- then go provoke Pals / ride around and watch whether they attack.
-- Press F6 again to release.

local POLL_MS  = 500
local PIN_KEY  = "F6"      -- toggle force-grade-0 (avoid R = hot-reload)

local function log(m) print("[PDST-Probe] " .. m .. "\n") end
local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end

local function player()
    local p; pcall(function() p = FindFirstOf("PalPlayerCharacter") end)
    return isValid(p) and p or nil
end
local function gradeComp(p)
    local c; pcall(function() c = p.CharacterParameterComponent end)
    return isValid(c) and c or nil
end
local function readGrade(p)
    local c = gradeComp(p); if not c then return nil end
    local g; local ok = pcall(function() g = c.BiologicalGrade end)
    return ok and g or nil
end
local function writeGrade(p, v)
    local c = gradeComp(p); if not c then return false end
    return pcall(function() c.BiologicalGrade = v end)
end

local pinned   = false     -- are we forcing grade to 0?
local baseline = nil       -- natural (unpinned) grade last seen -- what F6-off restores to
local lastRead = nil       -- last value printed (only log on change while unpinned)

-- Poll: unpinned -> log grade whenever it changes (foot<->mount shows up here). Pinned -> re-apply 0
-- each tick and, if it drifted back on its own, log that (means the game re-applies -> we must keep pinning).
LoopAsync(POLL_MS, function()
    local p = player(); if not p then return false end
    local g = readGrade(p); if g == nil then return false end
    if pinned then
        if g ~= 0 then log("grade drifted to " .. tostring(g) .. " on its own -> game re-applies; re-pinning 0") end
        writeGrade(p, 0)
    else
        baseline = g
        if g ~= lastRead then log("player BiologicalGrade = " .. tostring(g)); lastRead = g end
    end
    return false
end)

-- F6: toggle the forced grade
local okKey = pcall(function()
    RegisterKeyBind(Key[PIN_KEY], function()
        local p = player(); if not p then log(PIN_KEY .. ": no player found"); return end
        pinned = not pinned
        if pinned then
            local before = readGrade(p)
            writeGrade(p, 0)
            log(string.format("PIN ON  -> grade forced 0 (natural was %s, read-back %s). Provoke Pals / mount up and watch.",
                tostring(baseline), tostring(readGrade(p))))
            log("   (before=" .. tostring(before) .. ")")
        else
            writeGrade(p, baseline or 5); lastRead = nil
            log("PIN OFF -> restored grade to " .. tostring(baseline or 5) .. " (game recomputes it on state change anyway)")
        end
    end)
end)

log("grade probe loaded. Poll logs grade on change; press " .. PIN_KEY .. " to toggle force-grade-0."
    .. (okKey and "" or "  (WARNING: keybind registration failed -> read-only poll still runs)"))
