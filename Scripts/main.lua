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
--  IDLE = ZERO GAME-THREAD WORK. The tick only touches the game thread when the
--  watch-list is NON-EMPTY (i.e. something is actively hunting you). When nothing
--  is -- the overwhelming majority of playtime -- the async loop just peeks a Lua
--  table off-thread and returns, so there is no ExecuteInGameThread sync and no
--  FindFirstOf scan per tick. That constant per-tick game-thread hit was the
--  stutter people reported (its rhythm tracked tick_ms). The player pawn is also
--  cached and only re-fetched on death/respawn, so FindFirstOf isn't run per tick
--  even while you ARE being chased.
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
    probe               = true,    -- DEV ONLY (branch-only): perception-piggyback feasibility probe. STRIP BEFORE RELEASE.
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
local WATCH_N = 0   -- live count, so the async loop can gate on "anything hunting?" without game-thread work

-- Cached player pawn -- FindFirstOf is an all-UObjects scan, so we do it once and
-- only re-fetch when the cached pawn goes invalid (death/respawn), not every tick.
local PLAYER = nil
local function currentPlayer()
    if not isValid(PLAYER) then PLAYER = FindFirstOf("PalPlayerCharacter") end
    return isValid(PLAYER) and PLAYER or nil
end

-- The aggro event: a pal targeted the player. MINIMAL work here -- just record the
-- controller (valid mid-call); the tick does the LOS logic.
local function watchAdd(self)
    local ctrl = unwrap(self); if not isValid(ctrl) then return end
    local id = objId(ctrl)
    if id and not WATCH[id] then WATCH[id] = { ctrl = ctrl, noLOS = 0 }; WATCH_N = WATCH_N + 1; vlog("watch+ " .. id) end
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAIController:AddTargetPlayer_ForEnemy", function(self) watchAdd(self) end)
    end)
    log("hide-to-escape: AddTargetPlayer_ForEnemy hook " .. (ok and "registered" or "FAILED"))
end

local function watchDel(id, why) if WATCH[id] then WATCH[id] = nil; WATCH_N = WATCH_N - 1; vlog("drop " .. id .. " " .. why) end end

local function hideTick()
    if not CONFIG.hide_enabled or WATCH_N == 0 then return end
    local player = currentPlayer(); if not player then return end
    local ploc = getLoc(player); if not ploc then return end
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local base = math.max(1, math.floor(CONFIG.hide_seconds * 1000 / CONFIG.tick_ms + 0.5))
    local n = 0
    for id, e in pairs(WATCH) do
        local ctrl = e.ctrl
        if not isValid(ctrl) then
            watchDel(id, "despawned")
        elseif tpCount(ctrl) == 0 then
            watchDel(id, "tp=0 (dropped target itself)")
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
                    clearAggro(ctrl); watchDel(id, "hide-escape: " .. (e.cls or "?") .. " lost you")
                end
            else
                if e.noLOS > 0 then vlog(string.format("hunt %s SEES you d=%.0fm (reset)", e.cls or "?", d)) end
                e.noLOS = 0
            end
        end
    end
    if n > 0 then vlog("watch size=" .. n) end
end

-- IDLE FAST-PATH: peek WATCH_N off-thread (a plain Lua int) and only pay the
-- ExecuteInGameThread game-thread sync when something is actually hunting you.
-- Nothing hunting -> this loop is just an int compare + sleep, no game-thread hit.
LoopAsync(CONFIG.tick_ms, function()
    if CONFIG.hide_enabled and WATCH_N > 0 then
        ExecuteInGameThread(function() local ok,e = pcall(hideTick); if not ok then log("hideTick err " .. tostring(e)) end end)
    end
    return false
end)

-- ===== DEV STUTTER METER -- BRANCH ONLY, STRIP BEFORE RELEASE ================
-- Detects game-thread hitches independently of our tick. A fast sampler runs ON
-- the game thread every sample_ms; when a frame stalls, the queued sample fires
-- late and the measured wall-clock gap spikes. Reports the worst gap + how many
-- hitches per window -- a number you can compare between builds / machines even
-- when the stutter is too subtle to feel. os.clock() is wall-clock on Windows.
-- peakHunters ties each window to how big a chase was underway (the mid-chase
-- question): a worst-ms that climbs with peakHunters implicates the hunter loop.
-- enabled=false: stutter measurement is deprioritized (the piggyback rebuild is the
-- goal, not proving the hitch). Code kept in place to flip back on if ever needed.
local STUTTER = { enabled = false, sample_ms = 50, hitch_ms = 100, window = 100,
                  last = nil, worst = 0, hitches = 0, n = 0, peakHunters = 0, ok = true }
if STUTTER.enabled then
    LoopAsync(STUTTER.sample_ms, function()
        ExecuteInGameThread(function()
            if not STUTTER.ok then return end
            local now; pcall(function() now = os.clock() end)
            if not now then STUTTER.ok = false; log("stutter-meter: os.clock unavailable, disabled"); return end
            now = now * 1000
            if WATCH_N > STUTTER.peakHunters then STUTTER.peakHunters = WATCH_N end
            if STUTTER.last then
                local dt = now - STUTTER.last
                STUTTER.n = STUTTER.n + 1
                if dt > STUTTER.worst then STUTTER.worst = dt end
                if dt > STUTTER.hitch_ms then STUTTER.hitches = STUTTER.hitches + 1 end
                if STUTTER.n >= STUTTER.window then
                    log(string.format("stutter: worst %.0fms | hitches>%dms=%d/%d (~%.0fs window) | peakHunters=%d",
                        STUTTER.worst, STUTTER.hitch_ms, STUTTER.hitches, STUTTER.n,
                        STUTTER.n * STUTTER.sample_ms / 1000, STUTTER.peakHunters))
                    STUTTER.worst = 0; STUTTER.hitches = 0; STUTTER.n = 0; STUTTER.peakHunters = 0
                end
            end
            STUTTER.last = now
        end)
        return false
    end)
end
-- ===== END DEV STUTTER METER =================================================

-- ===== DEV PERCEPTION PROBE -- BRANCH ONLY, STRIP BEFORE RELEASE =============
-- Answers the ONE unknown blocking the "piggyback on the AI's own perception"
-- rebuild (classes found in the Palworld SDK dump). Every game call is pcall-
-- guarded and logged as an event, so a missing/renamed API degrades to "absent"
-- instead of crashing (the F10 probe of old crashed for lack of this).
--   Q1 CALL  -- reach a live hunter's UPalAISensorComponent, read its per-instance
--               SightDistance/cone, and call the pal's OWN sight test
--               (SightCheckAllPlayer) -- can we use real senses instead of our ray?
--   Q2 HOOK  -- is UPalAICombatModule:UpdateBattleState hookable, and does it fire
--               mid-chase? (so give-up logic can ride it instead of our LoopAsync)
--   Q3 EVENT -- does UPalAICombatModule_Wild:OnBattleFinish_forDelegate fire? (the
--               native end-of-battle we might lean on)
-- Get something hunting you, then press F10: Q1 runs and the Q2/Q3 tallies print.
local PROBE = { enabled = CONFIG.probe, battleTicks = 0, battleFinish = 0, announced = false }

-- StaticFindObject wants the class' object path; try the two spellings UE4SS accepts.
local function findClass(name)
    local c; pcall(function() c = StaticFindObject("Class /Script/Pal." .. name) end)
    if not isValid(c) then pcall(function() c = StaticFindObject("/Script/Pal." .. name) end) end
    return c
end

local function firstHunter()
    for _, e in pairs(WATCH) do
        local p = getPawn(e.ctrl); if isValid(p) then return p, e.ctrl end
    end
end

-- The sensor is a UActorComponent; SelfPawn hints it may live on the controller, not
-- the pawn -- so try both owners (fallback chain) before giving up.
local function getSensor(ctrl, pawn, cls)
    local s
    pcall(function() s = ctrl:GetComponentByClass(cls) end); if isValid(s) then return s, "controller" end
    pcall(function() s = pawn:GetComponentByClass(cls) end); if isValid(s) then return s, "pawn" end
end

local function probeSensor()
    if not currentPlayer() then log("PROBE Q1: no player"); return end
    local pawn, ctrl = firstHunter()
    if not isValid(pawn) then log("PROBE Q1: nothing hunting you -- get aggro first, then F10"); return end
    local species = classNameOf(pawn) or "?"
    local cls = findClass("PalAISensorComponent")
    if not isValid(cls) then log("PROBE Q1: PalAISensorComponent class NOT resolvable via StaticFindObject"); return end
    local sensor, owner = getSensor(ctrl, pawn, cls)
    if not isValid(sensor) then log("PROBE Q1: " .. species .. " -- no reachable sensor on controller OR pawn"); return end
    local sd, sa, hr
    pcall(function() sd = sensor.SightDistance end)
    pcall(function() sa = sensor.SightAngleThreshold end)
    pcall(function() hr = sensor.HearingRate end)
    log(string.format("PROBE Q1: %s sensor OK (on %s) -- SightDistance=%s cone=%s HearingRate=%s",
        species, owner, tostring(sd), tostring(sa), tostring(hr)))
    -- SightCheckAllPlayer's return shape varies across UE4SS builds; log whatever comes
    -- back so we learn how to read it (this is discovery, not a finished call site).
    local ok, ret = pcall(function() return sensor:SightCheckAllPlayer({}, 1.0) end)
    if not ok then log("PROBE Q1: SightCheckAllPlayer CALL FAILED -> " .. tostring(ret)); return end
    local n; pcall(function() if ret and ret.GetArrayNum then n = ret:GetArrayNum() end end)
    if n == nil and type(ret) == "table" then n = #ret end
    log("PROBE Q1: SightCheckAllPlayer returned type=" .. type(ret) .. " count=" .. tostring(n)
        .. " -- compare vs whether you were actually in view")
end

if PROBE.enabled then
    -- Q2/Q3 are passive: hook at load, count fires (UpdateBattleState is announced ONCE
    -- to avoid spam), and let F10 report the tallies.
    local ok2 = pcall(function()
        RegisterHook("/Script/Pal.PalAICombatModule:UpdateBattleState", function()
            PROBE.battleTicks = PROBE.battleTicks + 1
            if not PROBE.announced then PROBE.announced = true; log("PROBE Q2: UpdateBattleState IS firing (hookable, combat ticks)") end
        end)
    end)
    log("PROBE Q2: UpdateBattleState hook " .. (ok2 and "registered" or "FAILED"))
    local ok3 = pcall(function()
        RegisterHook("/Script/Pal.PalAICombatModule_Wild:OnBattleFinish_forDelegate", function()
            PROBE.battleFinish = PROBE.battleFinish + 1; log("PROBE Q3: OnBattleFinish_forDelegate fired (#" .. PROBE.battleFinish .. ")")
        end)
    end)
    log("PROBE Q3: OnBattleFinish_forDelegate hook " .. (ok3 and "registered" or "FAILED"))
    local okk = pcall(function()
        RegisterKeyBind(Key.F10, function()
            ExecuteInGameThread(function()
                local ok, e = pcall(probeSensor); if not ok then log("PROBE err " .. tostring(e)) end
                log(string.format("PROBE tally: UpdateBattleState=%d OnBattleFinish=%d", PROBE.battleTicks, PROBE.battleFinish))
            end)
        end)
    end)
    log("PROBE: F10 " .. (okk and "bound -- press F10 while hunted" or "bind FAILED (Key.F10 unavailable?)"))
end
-- ===== END DEV PERCEPTION PROBE =============================================

-- Level-gap sight (WoW-style) shipped as a DATA tier-approximation (tougher species
-- see further, which tracks zone level) -- an OLD probe concluded there was no per-
-- instance sight field. The SDK dump contradicts that: UPalAISensorComponent carries
-- per-instance SightDistance + SightAngleThreshold. The perception probe above (Q1)
-- is verifying whether those are readable/writable at runtime; if so, true per-you
-- sight scaling is back on the table (separate thread from hide-to-escape).

log("Predators & Stealth runtime v2 loaded. hide-to-escape " .. (CONFIG.hide_enabled and "ON" or "OFF")
    .. " (" .. CONFIG.hide_seconds .. "s no-LOS, >" .. CONFIG.hide_min_distance_m .. "m, crouch x" .. CONFIG.hide_crouch_mult .. ").")
