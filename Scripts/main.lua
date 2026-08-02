-- ============================================================================
--  Predators & Stealth -- runtime layer (v2, PalSchema-era)
--
--  Aggression + detection is a PalSchema DATA patch. This script is only the small
--  RUNTIME that data can't do:
--
--    * HIDE-TO-ESCAPE -- native de-aggro is LEASH-only, so break line-of-sight +
--      put distance between you and a pursuer and, after a few seconds, it gives up.
--
--  DESIGN:
--    - Pursuers are tracked in WATCH, fed by the CONTROLLER-side "targeted the player"
--      hook (AddTargetPlayer_ForEnemy) -- self = the controller, alive, safe to store.
--    - DRIVER = a hook on UPalAICombatModule:UpdateBattleState (the game's own combat
--      tick, fires whenever any pal is fighting). We use it purely as a "we're in combat
--      context now" trigger: on each fire we sweep the WATCH list and evaluate each
--      pursuer (throttled ~1/sec) IN the combat-tick context, where LineOfSightTo +
--      clearAggro behave. We do NOT touch the module `self` at all -- no Outer-walk to
--      find its controller (that walk, on a module ticking during teardown, was the
--      use-after-free crash: EXCEPTION_ACCESS_VIOLATION, pcall can't catch). So the hot
--      path has no unsafe touch. (Squad-copier coverage -- pals that never fire
--      AddTargetPlayer -- is a phase-2 feed.)
--    - "Can it see me" is LINE OF SIGHT ONLY (LineOfSightTo, default viewpoint -- the
--      published-build form that works) -- not the vision cone. Give-up uses an UNSEEN
--      accumulator that climbs out of sight and bleeds DOWN (not zeroes) on a glimpse.
--    - WATCHDOG = a slow idle-gated LoopAsync: safety net that evaluates pursuers the
--      hook missed, GCs despawned ones, enforces the death guard + the warp catch.
--    - DEATH SAFETY: on death Palworld tears down combat state; calling ANY UFunction
--      on the player/pursuer during that window hard-crashes (native access violation
--      pcall can't catch). livePlayer() (IsDead OR IsDying) gates EVERY path -- the
--      hook bails first thing, the watchdog drops all tracking -- so we touch nothing
--      until respawn settles.
--
--  Level-gap aggro stays a DATA tier-approximation. Per-instance sight IS settable
--  (UPalAISensorComponent.SightDistance) for a possible future feature; not here.
-- ============================================================================

local CONFIG = {
    hide_enabled        = true,
    hide_seconds        = 6,       -- seconds effectively-unseen before a FAR pursuer (>=min_distance) gives up
    hide_close_mult     = 1.25,    -- close pursuers (<min_distance) take a bit longer
    hide_min_distance_m = 20,      -- must be at least this far (point-blank never loses you)
    hide_crouch_mult    = 0.5,     -- crouching shortens BOTH the give-up time and the distance gate
    seen_decay          = 0.5,     -- while a pursuer sees you, the unseen timer bleeds DOWN at this x rate (glimpse tolerance)
    combat_hook         = true,    -- UpdateBattleState hook DRIVES eval, in combat-tick context (where LineOfSightTo + clearAggro behave). Crash-safe: it never touches the module `self` -- just sweeps WATCH. false = watchdog-only (still works, less native/responsive).
    eval_throttle_s     = 0.9,     -- min seconds between evals for one pursuer (hook fires ~17x/sec; this throttles to ~1 eval/sec)
    hook_sweep_s        = 0.3,     -- min seconds between WATCH sweeps triggered by the hook (so we don't iterate 17x/sec)
    watchdog_ms         = 1000,    -- watchdog cadence: safety-net eval + GC + warp/death guards; idle-gated on WATCH_N>0
    stale_s             = 0.5,     -- re-evaluate a pursuer if unchecked this long (< watchdog_ms => every cycle)
    warp_distance_m     = 100,     -- a player jump > this in one tick = a WARP (teleport/item/dungeon/zone/respawn) -> drop ALL tracking
    verbose             = true,    -- DEV(branch): per-pursuer countdowns + crash breadcrumbs ("op ..."). Off before release.
}

local function log(m) print("[PDST] " .. m .. "\n") end
local function vlog(m) if CONFIG.verbose then log(m) end end

local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end
local function objId(o) local n; pcall(function() n = o:GetFName():ToString() end); return n end
local function unwrap(o) local r = o; pcall(function() r = o:get() end); return r end
local function getPawn(ctrl) local p; pcall(function() p = ctrl:K2_GetPawn() end); return p end
local function classNameOf(a) local n; pcall(function() n = a:GetClass():GetFName():ToString() end); return n end
local function isPlayerActor(a) if not isValid(a) then return false end local cn = classNameOf(a); return cn ~= nil and cn:find("Player") ~= nil end
local function getLoc(a) local v; local ok=pcall(function() v=a:K2_GetActorLocation() end); if ok and v then local x,y,z; pcall(function() x=v.X;y=v.Y;z=v.Z end); if x then return {x=x,y=y,z=z} end end end
local function dist2(a,b) local dx=a.x-b.x;local dy=a.y-b.y;local dz=a.z-b.z;return dx*dx+dy*dy+dz*dz end
local function tpCount(ctrl) local n=0; pcall(function() n=ctrl.TargetPlayers:GetArrayNum() end); return n end
-- LOS: the game's own LineOfSightTo with DEFAULT viewpoint -- the published-build form
-- the user confirmed works. (The explicit-viewpoint variant this branch tried was the
-- regression; the custom cover-ray that replaced it broke de-aggro entirely.) Correct
-- when called from the combat-tick context (the hook), which is why the hook drives eval.
local function hasLOS(ctrl, player)
    local r = false; pcall(function() r = ctrl:LineOfSightTo(player, nil, false) end); return r
end

-- THE de-aggro call (confirmed safe): clear the hate map AND the active target list.
local function clearAggro(ctrl)
    local hs; pcall(function() hs = ctrl:GetHateSystem() end)
    if isValid(hs) then local hm; pcall(function() hm = hs.HateMap end); if hm ~= nil then pcall(function() hm:Empty() end) end end
    pcall(function() ctrl.TargetPlayers:Empty() end)
end

local PLAYER = nil
local function currentPlayer()
    if not isValid(PLAYER) then PLAYER = FindFirstOf("PalPlayerCharacter") end
    return isValid(PLAYER) and PLAYER or nil
end

-- The player, but only while ALIVE. On death/dying Palworld tears down combat state;
-- touching a pursuer's controller/hate/LOS then HARD-crashes (native access violation
-- pcall cannot catch), so every path bails until respawn settles. IsDead/IsDying are
-- cheap UFunctions on PalCharacter.
local function livePlayer()
    local p = currentPlayer(); if not p then return nil end
    local out = false; pcall(function() out = p:IsDead() or p:IsDying() end)
    if out then return nil end
    return p
end

-- WATCH: objId(ctrl) -> { ctrl, id, cls?, lastEval?, unseen? }. Keyed by controller;
-- we never track the combat module (that's what forced the crashing Outer-walk).
local WATCH    = {}
local WATCH_N  = 0
local PREV_LOC = nil   -- player location last tick; a huge one-tick jump = a warp -> forgetAll (generic warp catch)

local function prune(e)
    if e.id and WATCH[e.id] then WATCH[e.id] = nil; WATCH_N = WATCH_N - 1 end
end

local function forgetAll()   -- drop ALL tracking (Lua-only, touches no game objects) -- death / warp
    for k in pairs(WATCH) do WATCH[k] = nil end
    WATCH_N = 0; PREV_LOC = nil
end

local function ensureEntry(ctrl)
    local id = objId(ctrl); if not id then return end
    local e = WATCH[id]
    if not e then e = { ctrl = ctrl, id = id }; WATCH[id] = e; WATCH_N = WATCH_N + 1; vlog("watch+ " .. id) end
    return e
end

-- ---------------------------------------------------------------------------
--  Give-up evaluation (game thread only). Time-based (os.clock), cadence-agnostic.
-- ---------------------------------------------------------------------------
local function evaluate(e, ctrl, now)
    vlog("op eval " .. (e.id or "?"))   -- crash breadcrumb: if this is the last "op" line, we died evaluating this pursuer
    local player = livePlayer(); if not player then prune(e); return end   -- YOU dead/dying: touch no pursuers
    local pawn = getPawn(ctrl)
    if not isValid(pawn) then prune(e); return end
    -- A PURSUER dying in a big fight is torn down too: LineOfSightTo/GetHateSystem on its
    -- controller then derefs the null pawn and hard-crashes. Skip + drop it if it's dead/dying.
    local pdead = false; pcall(function() pdead = pawn:IsDead() or pawn:IsDying() end)
    if pdead or tpCount(ctrl) == 0 then prune(e); return end
    if not e.cls then e.cls = classNameOf(pawn) end
    local ploc = getLoc(player); if not ploc then return end
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local dt = e.lastEval and (now - e.lastEval) or 0
    e.lastEval = now

    local pl = getLoc(pawn)
    local d = pl and (math.sqrt(dist2(pl, ploc)) / 100) or -1   -- metres
    local gateM = crouched and (CONFIG.hide_min_distance_m * CONFIG.hide_crouch_mult) or CONFIG.hide_min_distance_m
    local far = d >= 0 and d >= gateM
    local needed = far and CONFIG.hide_seconds or (CONFIG.hide_seconds * CONFIG.hide_close_mult)
    if crouched then needed = needed * CONFIG.hide_crouch_mult end

    -- "Unseen" accumulator: climbs while out of sight, bleeds DOWN while seen (not zeroes),
    -- so a brief glimpse doesn't restart the timer but steady sight keeps a pursuer locked on.
    e.unseen = e.unseen or 0
    local sees = hasLOS(ctrl, player)                          -- game's own LOS (published form)
    if sees then
        e.unseen = math.max(0, e.unseen - dt * CONFIG.seen_decay)
    else
        e.unseen = e.unseen + dt
    end
    vlog(string.format("hunt %s unseen %.1f/%.1fs d=%.0fm", e.cls or "?", e.unseen, needed, d))
    if e.unseen >= needed then
        clearAggro(ctrl); prune(e)
        log("hide-escape: " .. (e.cls or "?") .. " lost you")
    end
end

-- Feed: a pal directly targeted the player. self = the CONTROLLER, valid mid-call --
-- the safe moment to record it. (We track the controller, never the combat module.)
local function watchAdd(self)
    local ctrl = unwrap(self); if not isValid(ctrl) then return end
    ensureEntry(ctrl)
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAIController:AddTargetPlayer_ForEnemy", function(self) watchAdd(self) end)
    end)
    log("hide-to-escape: AddTargetPlayer_ForEnemy hook " .. (ok and "registered" or "FAILED"))
end

-- resolveController: module -> its owning PalAIController, by walking the Outer chain
-- and matching class name (safe to read on any UObject). ONLY called from OnBattleFinish
-- below -- the game's explicit "battle ending" event, where the module + its controller
-- are still alive (teardown hasn't freed them yet). It is deliberately NOT used in the
-- combat-tick hot path (UpdateBattleState), where a teardown-phase module would crash it.
local function resolveController(module)
    local o = module
    for _ = 1, 6 do
        local nxt; pcall(function() nxt = o:GetOuter() end)
        if not isValid(nxt) then return end
        o = nxt
        local cn = classNameOf(o)
        if cn and cn:find("AIController") then return o end
    end
end

-- ---------------------------------------------------------------------------
--  DRIVER: the game's combat tick fires this ~17x/sec while any pal is fighting. We use
--  it ONLY as a "we're in combat context now" trigger -- we IGNORE the module `self`
--  entirely (no Outer-walk, no touch = no use-after-free) and instead sweep our own WATCH
--  list, evaluating each pursuer in this context (where LineOfSightTo + clearAggro behave).
--  Throttled so we sweep a few times/sec, not on every one of the ~17 fires.
-- ---------------------------------------------------------------------------
local DRIVE_ANNOUNCED = false
local lastHookSweep = nil
local function onBattleTick()
    if not CONFIG.hide_enabled or WATCH_N == 0 then return end
    if not livePlayer() then return end                  -- dead/dying: touch no pursuers (death-crash guard)
    local now = os.clock()
    if lastHookSweep and (now - lastHookSweep) < CONFIG.hook_sweep_s then return end
    lastHookSweep = now
    if not DRIVE_ANNOUNCED then DRIVE_ANNOUNCED = true; log("hide-to-escape: driven by UpdateBattleState (combat-tick context)") end
    for _, e in pairs(WATCH) do
        local ctrl = e.ctrl
        if not isValid(ctrl) or tpCount(ctrl) == 0 then
            prune(e)
        elseif not e.lastEval or (now - e.lastEval) >= CONFIG.eval_throttle_s then
            evaluate(e, ctrl, now)
        end
    end
end
if CONFIG.hide_enabled and CONFIG.combat_hook then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAICombatModule:UpdateBattleState", function() onBattleTick() end)
    end)
    log("hide-to-escape: UpdateBattleState hook " .. (ok and "registered" or "FAILED"))
else
    log("hide-to-escape: UpdateBattleState hook OFF -- watchdog-only driver")
end

-- ---------------------------------------------------------------------------
--  PRUNE-ON-DESTROY: when a pursuer's battle ends (leash / give-up / death / our own
--  clearAggro), the game tears down its combat state and soon frees the controller.
--  Inside THIS event the module is still valid, so it's the safe moment to drop our
--  tracking -- so no later tick/hook pokes the freed object. Event-driven, not polled.
-- ---------------------------------------------------------------------------
local function onBattleFinish(self)
    local module = unwrap(self); if not isValid(module) then return end
    -- module is valid inside its own event, so the Outer-walk to its controller is safe here.
    local ctrl = resolveController(module); if not isValid(ctrl) then return end
    local id = objId(ctrl); if not id then return end
    local e = WATCH[id]
    if e then prune(e); vlog("prune battle-finished " .. id) end
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAICombatModule:OnBattleFinish", function(self) onBattleFinish(self) end)
    end)
    log("hide-to-escape: OnBattleFinish hook " .. (ok and "registered" or "FAILED"))
end

-- Also drop a pursuer when the game DEACTIVATES its AI (despawn / cull / streamed out).
-- OnBattleFinish only covers a clean give-up; a pal freed while still "in combat" slips
-- past it, and touching its zombie controller on the next tick is the crash. self = the
-- controller, valid inside this call. Only prune on deactivate (activate = no-op for us).
local function onSetActiveAI(self, active)
    if type(active) == "userdata" then pcall(function() active = active:get() end) end
    if active then return end                       -- activating -> not our concern
    local ctrl = unwrap(self); if not isValid(ctrl) then return end
    local id = objId(ctrl); if not id then return end
    local e = WATCH[id]
    if e then prune(e); vlog("prune deactivated " .. id) end
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAIController:SetActiveAI", function(self, active) onSetActiveAI(self, active) end)
    end)
    log("hide-to-escape: SetActiveAI hook " .. (ok and "registered" or "FAILED"))
end

-- Also drop a pursuer the instant IT dies -- you killing a pursuer (or anything killing it)
-- frees its controller, and neither OnBattleFinish nor SetActiveAI reliably fires for a
-- mid-combat kill (that gap = the watchdog poking the freed controller = use-after-free).
-- OnDeadTimerStart fires ON the controller when its pal dies, starting the dead-body timer:
-- self is still valid here, so it's the safe pre-free moment to prune. self = controller.
local function onDeadTimerStart(self)
    local ctrl = unwrap(self); if not isValid(ctrl) then return end
    local id = objId(ctrl); if not id then return end
    local e = WATCH[id]
    if e then prune(e); vlog("prune dead " .. id) end
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAIController:OnDeadTimerStart", function(self) onDeadTimerStart(self) end)
    end)
    log("hide-to-escape: OnDeadTimerStart hook " .. (ok and "registered" or "FAILED"))
end

-- ---------------------------------------------------------------------------
--  Watchdog: safety net + GC + death-guard enforcer. Off-thread it reads only
--  WATCH_N; it hops to the game thread to service pursuers the hook hasn't reached
--  in stale_s and to drop despawned/de-targeted ones (or ALL, if the player is dead).
-- ---------------------------------------------------------------------------
local function watchdogTick()
    local player = livePlayer()
    if not player then forgetAll(); return end            -- dead/dying: drop all tracking, touch nothing
    -- WARP CATCH: teleport / item-warp / dungeon / zone / respawn all move the player a huge
    -- distance in one tick and despawn the old area's pals at once. Detect the jump and drop
    -- everything BEFORE we touch a corpse -- one check instead of hooking every warp source.
    local ploc = getLoc(player)
    if ploc then
        local wd = CONFIG.warp_distance_m * 100
        if PREV_LOC and dist2(ploc, PREV_LOC) >= wd * wd then
            forgetAll(); vlog("player warped -> dropped all tracking"); PREV_LOC = ploc; return
        end
        PREV_LOC = ploc
    end
    vlog("op watchdog n=" .. WATCH_N)                     -- crash breadcrumb: distinguishes watchdog poke from the hook's objId
    local now = os.clock()
    for _, e in pairs(WATCH) do
        local ctrl = e.ctrl
        if not isValid(ctrl) or tpCount(ctrl) == 0 then
            prune(e)
        elseif not e.lastEval or (now - e.lastEval) >= CONFIG.stale_s then
            evaluate(e, ctrl, now)
        end
    end
end
if CONFIG.hide_enabled then
    LoopAsync(CONFIG.watchdog_ms, function()
        if WATCH_N > 0 then
            ExecuteInGameThread(function() local ok,err = pcall(watchdogTick); if not ok then log("watchdog err " .. tostring(err)) end end)
        end
        return false
    end)
end

-- ===== DEV STUTTER METER -- BRANCH ONLY, STRIP BEFORE RELEASE ================
-- Detects game-thread hitches independently of our logic. A fast sampler runs ON the
-- game thread every sample_ms; when a frame stalls, the queued sample fires late and
-- the wall-clock gap spikes. Reports worst gap + hitches per ~5s window -- comparable
-- across builds even when the hitch is too subtle to feel. peakHunters ties each
-- window to how big a chase was underway (does worst-ms climb with the pack?).
local STUTTER = { enabled = true, sample_ms = 50, hitch_ms = 100, window = 100,
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

log("Predators & Stealth runtime v3 loaded. hide-to-escape " .. (CONFIG.hide_enabled and "ON" or "OFF")
    .. " (" .. CONFIG.hide_seconds .. "s no-sight, >" .. CONFIG.hide_min_distance_m .. "m, crouch x" .. CONFIG.hide_crouch_mult .. ").")
