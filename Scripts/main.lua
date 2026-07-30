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
    hide_seconds        = 4,       -- no-LOS time before a FAR pursuer (>=min_distance) gives up
    hide_close_mult     = 1.5,     -- close pursuers (<min_distance) take this much longer -> ~6s
    hide_min_distance_m = 20,      -- must be at least this far (point-blank never loses you)
    hide_crouch_mult    = 0.5,     -- crouching halves BOTH the time and the distance
    tick_ms             = 1000,    -- how often we re-check the (small) hunter list
    verbose             = false,   -- set true to log each pursuer's give-up countdown
}

local function log(m) print("[PDST] " .. m .. "\n") end
local function vlog(m) if CONFIG.verbose then log(m) end end

local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end
local function objId(o) local n; pcall(function() n = o:GetFName():ToString() end); return n end
local function unwrap(o) local r = o; pcall(function() r = o:get() end); return r end
local function getPawn(ctrl) local p; pcall(function() p = ctrl:K2_GetPawn() end); return p end
local function classNameOf(a) local n; pcall(function() n = a:GetClass():GetFName():ToString() end); return n end
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

-- The aggro event: a pal targeted the player. MINIMAL work here -- just record the
-- controller (valid mid-call); the tick does the LOS logic.
local function watchAdd(self)
    local ctrl = unwrap(self); if not isValid(ctrl) then return end
    local id = objId(ctrl)
    if id and not WATCH[id] then WATCH[id] = { ctrl = ctrl, noLOS = 0 }; vlog("watch+ " .. id) end
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAIController:AddTargetPlayer_ForEnemy", function(self) watchAdd(self) end)
    end)
    log("hide-to-escape: AddTargetPlayer_ForEnemy hook " .. (ok and "registered" or "FAILED"))
end

local function hideTick()
    if not CONFIG.hide_enabled then return end
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then return end
    local ploc = getLoc(player); if not ploc then return end
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local base = math.max(1, math.floor(CONFIG.hide_seconds * 1000 / CONFIG.tick_ms + 0.5))
    local n = 0
    for id, e in pairs(WATCH) do
        local ctrl = e.ctrl
        if not isValid(ctrl) then
            WATCH[id] = nil; vlog("drop " .. id .. " despawned")
        elseif tpCount(ctrl) == 0 then
            WATCH[id] = nil; vlog("drop " .. id .. " tp=0 (dropped target itself)")
        else
            n = n + 1
            if not e.cls then e.cls = classNameOf(getPawn(ctrl)) end
            local loc = getLoc(getPawn(ctrl))
            local d = loc and (math.sqrt(dist2(loc, ploc)) / 100) or -1     -- metres
            local gateM = crouched and (CONFIG.hide_min_distance_m * CONFIG.hide_crouch_mult) or CONFIG.hide_min_distance_m
            local far = d >= 0 and d >= gateM
            if not hasLOS(ctrl, player) then
                -- No line of sight -> give up. Far = base time; close = a bit longer, but it STILL
                -- gives up (a searching pal circling within range no longer stays mad forever).
                local needed = far and base or math.max(base + 1, math.ceil(base * CONFIG.hide_close_mult))
                if crouched then needed = math.max(1, math.ceil(needed * CONFIG.hide_crouch_mult)) end
                e.noLOS = e.noLOS + 1
                vlog(string.format("hunt %s noLOS %d/%d d=%.0fm", e.cls or "?", e.noLOS, needed, d))
                if e.noLOS >= needed then
                    clearAggro(ctrl); WATCH[id] = nil
                    vlog("hide-escape: " .. (e.cls or "?") .. " lost you")
                end
            else
                if e.noLOS > 0 then vlog(string.format("hunt %s SEES you d=%.0fm (reset)", e.cls or "?", d)) end
                e.noLOS = 0
            end
        end
    end
    if n > 0 then vlog("watch size=" .. n) end
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
