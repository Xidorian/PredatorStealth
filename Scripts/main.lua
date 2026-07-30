-- ============================================================================
--  Predators & Stealth -- runtime layer (v2, PalSchema-era)
--
--  Aggression + detection (sight range/cone/LOS + crouch-stealth via hearing) is
--  now a PalSchema DATA patch (AIResponse=Warlike + per-pal ViewingDistance /
--  HearingRate). This script is only the small RUNTIME that data can't express:
--
--    * HIDE-TO-ESCAPE -- native de-aggro is LEASH-only, so break line-of-sight +
--      put distance between you and a pursuer gives up (clears hate + target).
--      Fed by a HOOK on the "pal targeted the player" event -> a tiny watch-list
--      of only the pals actually hunting you. NO world scan (that was the stutter).
--
--  Level-gap aggro (WoW-style) is handled in DATA as a tier-approximation (tougher
--  species get bigger ViewingDistance, which tracks zone level) -- probed and there
--  is no per-instance sight field to do true per-you scaling, and a proximity poll
--  would just re-introduce the stutter. So this script does hide-to-escape only.
-- ============================================================================

local CONFIG = {
    hide_enabled        = true,
    hide_seconds        = 7,       -- no-LOS time before a far pursuer gives up
    hide_min_distance_m = 20,      -- must be at least this far (point-blank never loses you)
    hide_crouch_mult    = 0.5,     -- crouching halves BOTH the time and the distance
    tick_ms             = 1000,    -- how often we re-check the (small) hunter list
    verbose             = false,   -- set true to log each hide-to-escape de-aggro
}

local function log(m) print("[PDST] " .. m .. "\n") end
local function vlog(m) if CONFIG.verbose then log(m) end end

local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end
local function objId(o) local n; pcall(function() n = o:GetFName():ToString() end); return n end
local function unwrap(o) local r = o; pcall(function() r = o:get() end); return r end
local function getPawn(ctrl) local p; pcall(function() p = ctrl:K2_GetPawn() end); return p end
local function getLoc(a) local v; local ok=pcall(function() v=a:K2_GetActorLocation() end); if ok and v then local x,y,z; pcall(function() x=v.X;y=v.Y;z=v.Z end); if x then return {x=x,y=y,z=z} end end end
local function dist2(a,b) local dx=a.x-b.x;local dy=a.y-b.y;local dz=a.z-b.z;return dx*dx+dy*dy+dz*dz end
local function tpCount(ctrl) local n=0; pcall(function() n=ctrl.TargetPlayers:GetArrayNum() end); return n end
local function hasLOS(ctrl, player) local r=false; pcall(function() r=ctrl:LineOfSightTo(player, nil, false) end); return r end

-- THE de-aggro call (confirmed safe): clear the hate map AND the active target list.
local function clearAggro(ctrl)
    local hs; pcall(function() hs = ctrl:GetHateSystem() end)
    if isValid(hs) then local hm; pcall(function() hm = hs.HateMap end); if hm ~= nil then pcall(function() hm:Empty() end) end end
    pcall(function() ctrl.TargetPlayers:Empty() end)
end

-- WATCH: pals currently hunting the player. objId -> {ctrl=, noLOS=ticks}. Fed by
-- the aggro hook (event), drained by the tick. Small -- only active hunters, so no scan.
local WATCH = {}

-- The aggro event: a pal added the player as an enemy target. MINIMAL work here --
-- just record the controller (it's valid mid-call); the tick does the LOS logic.
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAIController:AddTargetPlayer_ForEnemy", function(self)
            local ctrl = unwrap(self)
            if not isValid(ctrl) then return end
            local id = objId(ctrl)
            if id and not WATCH[id] then WATCH[id] = { ctrl = ctrl, noLOS = 0 } end
        end)
    end)
    log("hide-to-escape: AddTargetPlayer_ForEnemy hook " .. (ok and "registered" or "FAILED"))
end

local function hideTick()
    if not CONFIG.hide_enabled then return end
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then return end
    local ploc = getLoc(player); if not ploc then return end
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local hide_ticks = math.max(1, math.floor(CONFIG.hide_seconds * 1000 / CONFIG.tick_ms + 0.5))
    for id, e in pairs(WATCH) do
        local ctrl = e.ctrl
        if not isValid(ctrl) then
            WATCH[id] = nil                                   -- despawned
        elseif tpCount(ctrl) == 0 then
            WATCH[id] = nil                                   -- gave up on its own
        else
            local pawn = getPawn(ctrl); local loc = pawn and getLoc(pawn)
            local gateM = crouched and (CONFIG.hide_min_distance_m * CONFIG.hide_crouch_mult) or CONFIG.hide_min_distance_m
            local far = loc and (dist2(loc, ploc) >= (gateM * 100) ^ 2)
            if (not hasLOS(ctrl, player)) and far then
                local needed = crouched and math.max(1, math.ceil(hide_ticks * CONFIG.hide_crouch_mult)) or hide_ticks
                e.noLOS = e.noLOS + 1
                if e.noLOS >= needed then
                    clearAggro(ctrl); WATCH[id] = nil
                    vlog("hide-escape: a pursuer lost you")
                end
            else
                e.noLOS = 0                                    -- sees you, or too close
            end
        end
    end
end

LoopAsync(CONFIG.tick_ms, function()
    ExecuteInGameThread(function() local ok,e = pcall(hideTick); if not ok then log("hideTick err " .. tostring(e)) end end)
    return false
end)

-- Level-gap sight (WoW-style) was probed and is NOT doable per-instance: a pal has
-- no ViewingDistance field of its own (it's read from DT_PalMonsterParameter per
-- species). So level-gap stays a DATA tier-approximation (tougher species see
-- further), which tracks zone level anyway. No runtime for it -> no scan -> no stutter.

log("Predators & Stealth runtime v2 loaded. hide-to-escape " .. (CONFIG.hide_enabled and "ON" or "OFF")
    .. " (" .. CONFIG.hide_seconds .. "s no-LOS, >" .. CONFIG.hide_min_distance_m .. "m, crouch x" .. CONFIG.hide_crouch_mult .. ").")
