-- grade_probe.lua v2 -- DEV PROBE for the mounted-aggro / BiologicalGrade plan. TEMPORARY: delete +
-- drop the require before any release. Touches only the PLAYER and the player's OWN MOUNT (both stable
-- actors -- never volatile wild-pal AI), all pcall/isValid guarded, so it's crash-safe.
--
-- v1 finding: the player's BiologicalGrade is 0 on foot AND while mounted (it never changed). So the
-- "you read as the mount's grade" happens on the MOUNT Pal, not on you -- pinning YOUR grade is a
-- no-op. v2 therefore finds the mount and reads/pins ITS grade too.
--
-- ANSWERS NOW:
--   1. While riding, what is the MOUNT's BiologicalGrade? (expect ~5 -- the value wild Pals react to)
--   2. If we pin the mount's grade to 0, do wild Pals start attacking the mounted player? -> the fix.
--
-- USE: mount a Pal. Press F6 -> logs the mount's name + natural grade, then forces player AND mount
-- grade to 0 (re-pins each poll, logs any drift). Ride around / provoke wild Pals and watch. F6 again
-- = release + restore. Watch UE4SS.log for [PDST-Probe] lines.

local POLL_MS = 500
local function log(m) print("[PDST-Probe] " .. m .. "\n") end
local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end

local function player()
    local p; pcall(function() p = FindFirstOf("PalPlayerCharacter") end)
    return isValid(p) and p or nil
end
local function nameOf(a) local n; pcall(function() n = a:GetFName():ToString() end); return n or "?" end
local function gradeComp(a)
    local c; pcall(function() c = a.CharacterParameterComponent end)
    return isValid(c) and c or nil
end
local function readGrade(a)
    local c = gradeComp(a); if not c then return nil end
    local g; local ok = pcall(function() g = c.BiologicalGrade end); return ok and g or nil
end
local function writeGrade(a, v)
    local c = gradeComp(a); if not c then return false end
    return pcall(function() c.BiologicalGrade = v end)
end

-- The Pal the player is riding: the one active ride-marker with a live rider (single-player = one).
-- A ride-marker component's Outer is its owning actor = the mount.
local function findMount()
    local markers; pcall(function() markers = FindAllOf("PalRideMarkerComponent") end)
    if type(markers) ~= "table" then return nil end
    for _, m in ipairs(markers) do
        if isValid(m) then
            local rider; pcall(function() rider = m:GetRiderCharacter() end)
            if isValid(rider) then
                local mount; pcall(function() mount = m:GetOuter() end)
                if isValid(mount) then return mount end
            end
        end
    end
    return nil
end

local pinned, mount, mountNatural, lastPlayer = false, nil, nil, nil

LoopAsync(POLL_MS, function()
    local p = player(); if not p then return false end
    local pg = readGrade(p)
    if pinned then
        writeGrade(p, 0)                                          -- player (already 0; harmless)
        if isValid(mount) then
            local mg = readGrade(mount)
            if mg ~= nil and mg ~= 0 then log("mount grade drifted to " .. tostring(mg) .. " on its own -> game re-applies; re-pinning 0") end
            writeGrade(mount, 0)
        end
    else
        if pg ~= nil and pg ~= lastPlayer then log("player BiologicalGrade = " .. tostring(pg) .. " (foot or mounted)"); lastPlayer = pg end
    end
    return false
end)

local okKey = pcall(function()
    RegisterKeyBind(Key.F6, function()
        local p = player(); if not p then log("F6: no player"); return end
        pinned = not pinned
        if pinned then
            mount = findMount()
            if isValid(mount) then
                mountNatural = readGrade(mount)
                log("PIN ON  -> mount '" .. nameOf(mount) .. "' natural grade = " .. tostring(mountNatural)
                    .. "  ->  forcing player + mount to 0. Ride around / provoke wild Pals and watch.")
                writeGrade(p, 0); writeGrade(mount, 0)
            else
                log("PIN ON  -> player grade 0, but NO MOUNT FOUND -- are you actually riding a Pal? Mount up first, then toggle F6 again.")
                writeGrade(p, 0)
            end
        else
            writeGrade(p, 0)
            if isValid(mount) then writeGrade(mount, mountNatural or 5) end
            log("PIN OFF -> restored (mount grade back to " .. tostring(mountNatural) .. "; game recomputes on state change anyway).")
            mount, mountNatural = nil, nil
        end
    end)
end)

log("grade probe v2 loaded. MOUNT a Pal, then press F6 -> reports the mount's grade + pins it to 0. F6 again = off."
    .. (okKey and "" or "  (WARNING: keybind failed -> read-only poll still runs)"))
