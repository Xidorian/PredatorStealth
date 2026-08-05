-- mount_aggro.lua -- Predators & Stealth: keep wild Pals hunting you while MOUNTED.
--
-- WHY: a wild "Warlike" Pal stands down against a HIGHER biological grade (Discover_Greater -> flee/
-- ignore). Mounted, wild Pals perceive your MOUNT's grade (e.g. Garm = 3), which is > your grade (0),
-- so they leave you alone. Confirmed live with the grade probe: pinning the mount's BiologicalGrade
-- to 0 makes wild Pals attack a mounted player; restoring it makes them stop.
--
-- FIX: while you ride a Pal, pin THAT Pal's BiologicalGrade to 0 so wild Pals read a weak target and
-- engage. This lets the aggression data patch use plain "Warlike" everywhere -- wild Pals still
-- grade-check EACH OTHER, so no inter-Pal brawl -- instead of the blanket "Warlike_Anyway" (which
-- removed the grade check globally and made Pals attack everything).
--
-- SAFETY: touches only the player's OWN MOUNT (a stable, summoned actor -- never volatile wild-pal
-- AI), on the discrete ride start/end UFunctions, all pcall/isValid guarded. The grade write STICKS
-- (the game doesn't re-apply it -- measured over a long ride), so this is set-once per ride: no
-- polling, no per-tick work, nothing on the game thread.
--
-- HOOKS: UPalRiderComponent:Ride(Marker, ...) = mount up (Marker's Outer is the mount actor);
--        UPalRiderComponent:GetOff(...)        = dismount (restore the mount's natural grade).

local function log(m) print("[PDST-Mount] " .. m .. "\n") end
local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end
local function uw(o) local r = o; pcall(function() r = o:get() end); return r end   -- unwrap a hook param
local function nameOf(a) local n; pcall(function() n = a:GetFName():ToString() end); return n or "?" end

-- a ride-marker component's Outer is its owning actor = the mount Pal
local function mountFromMarker(marker)
    if not isValid(marker) then return nil end
    local m; pcall(function() m = marker:GetOuter() end)
    return isValid(m) and m or nil
end
local function paramComp(actor)
    local c; pcall(function() c = actor.CharacterParameterComponent end)
    return isValid(c) and c or nil
end
local function restoreGrade(actor)
    local c = paramComp(actor); if not c then return end
    pcall(function() c:SetupBiologicalGradeFromDatabase() end)   -- re-derive the natural grade from the DB
end

local pinnedMount = nil   -- the mount we forced to grade 0 (held only to restore it on dismount)

-- RIDE START: pin the mount's grade to 0.
local function onRide(self, marker)
    local m = mountFromMarker(uw(marker))
    if not m then return end
    if isValid(pinnedMount) then restoreGrade(pinnedMount) end   -- clear any previous mount first
    local c = paramComp(m); if not c then return end
    local before; pcall(function() before = c.BiologicalGrade end)
    pcall(function() c.BiologicalGrade = 0 end)
    pinnedMount = m
    log("ride start: mount '" .. nameOf(m) .. "' grade " .. tostring(before) .. " -> 0 (wild Pals will now hunt you mounted)")
end

-- RIDE END: restore the mount's natural grade.
local function onGetOff()
    if isValid(pinnedMount) then
        restoreGrade(pinnedMount)
        log("ride end: mount '" .. nameOf(pinnedMount) .. "' grade restored from DB")
    end
    pinnedMount = nil
end

local okR = pcall(function() RegisterHook("/Script/Pal.PalRiderComponent:Ride",   function(self, marker) onRide(self, marker) end) end)
local okG = pcall(function() RegisterHook("/Script/Pal.PalRiderComponent:GetOff", function(self) onGetOff() end) end)
log("mounted-aggro loaded. ride-hook=" .. tostring(okR) .. " getoff-hook=" .. tostring(okG)
    .. (okR and "" or " -- WARNING: ride hook failed to register"))
