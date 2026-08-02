-- ============================================================================
--  Predators & Stealth -- runtime layer (v3, RESOLVE-LIVE)
--
--  Aggression + detection is a PalSchema DATA patch. This script is the small RUNTIME
--  the data can't do: HIDE-TO-ESCAPE -- native de-aggro is LEASH-only, so break line of
--  sight + get distance and, after a few seconds, a pursuer gives up.
--
--  CRASH-SAFE ARCHITECTURE (resolve-live). Every use-after-free crash came from HOLDING a
--  pursuer's controller/module reference and touching it on a LATER tick, after the game
--  had freed it (death / flee / despawn / teleport). isValid() can't catch a freed "zombie",
--  and no set of prune hooks covers every way a pal can leave. So we stop holding references:
--    - We only ever touch a pursuer INSIDE the game's own UPalAICombatModule:UpdateBattleState
--      call for it. `self` there is a LIVE module the game is actively ticking this frame, so
--      it -- and the controller that owns it -- are alive right now. We resolve the controller,
--      evaluate, act, and let go. Nothing is stored to poke next tick.
--    - Per-pursuer state (the give-up timer) lives in TRACK keyed by the module's NAME -- a
--      string, not a pointer, so it can never go stale. A pursuer that leaves simply stops
--      firing UpdateBattleState; its TRACK entry ages out via a pure-timestamp GC that touches
--      NO game object. Death / flee / despawn / teleport / your own death are all self-healing
--      with ZERO teardown hooks and zero chance of poking a freed object.
--  Bonus: we see EVERY battling module targeting the player, so squad-mates that inherited the
--  target without sighting you directly are covered too.
--
--  "Can it see me" = LineOfSightTo (default viewpoint -- the published form that works),
--  run in the combat-tick context where it and clearAggro behave. Give-up uses an UNSEEN
--  accumulator that climbs out of sight and bleeds DOWN (not zeroes) on a glimpse.
-- ============================================================================

local CONFIG = {
    hide_enabled        = true,
    hide_seconds        = 6,       -- seconds effectively-unseen before a FAR pursuer (>=min_distance) gives up
    hide_close_mult     = 1.25,    -- close pursuers (<min_distance) take a bit longer
    hide_min_distance_m = 20,      -- must be at least this far (point-blank never loses you)
    hide_crouch_mult    = 0.5,     -- crouching shortens BOTH the give-up time and the distance gate
    seen_decay          = 0.5,     -- while a pursuer sees you, the unseen timer bleeds DOWN at this x rate (glimpse tolerance)
    eval_throttle_s     = 0.9,     -- per-pursuer: min seconds between resolve+eval (hook fires ~17x/sec; we act ~1x/sec)
    stale_s             = 3.0,     -- drop a TRACK entry if its module hasn't ticked in this long (the pal left combat)
    gc_ms               = 1000,    -- staleness-GC cadence (pure Lua; touches no game objects)
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

-- "Can it see me": the game's own LineOfSightTo, default viewpoint (published form that works).
local function hasLOS(ctrl, player)
    local r = false; pcall(function() r = ctrl:LineOfSightTo(player, nil, false) end); return r
end

-- THE de-aggro call (confirmed working): clear the hate map AND the active target list.
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
-- The player, but only while ALIVE. On death Palworld tears down combat state; touching the
-- player (or a pursuer) during that window hard-crashes. Every path bails until respawn settles.
local function livePlayer()
    local p = currentPlayer(); if not p then return nil end
    local out = false; pcall(function() out = p:IsDead() or p:IsDying() end)
    if out then return nil end
    return p
end

-- TRACK: module-name(string) -> { unseen, lastEval, lastSeen, cls }. Keys and values are
-- plain data (strings/numbers) only -- NEVER a game-object reference, so nothing here can
-- go stale or crash when poked. This is the whole point of the resolve-live design.
local TRACK = {}
local function trackCount() local n = 0; for _ in pairs(TRACK) do n = n + 1 end; return n end

-- resolveController: LIVE module -> its owning PalAIController, via the Outer chain, matched
-- by class name (safe to read on any UObject). ONLY called on a module the game is ACTIVELY
-- ticking this frame (inside its own UpdateBattleState, gated on GetTargetActor==player AND
-- IsBattleMode), so the module and the owner it walks up to are alive. This is the one place
-- that reaches a game object we didn't just receive as `self`; the `op resolve` breadcrumb
-- marks it so a crash here (should one ever happen) is unambiguous.
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

-- Give-up evaluation. ctrl is LIVE (just resolved from the live module). Time-based
-- (os.clock), cadence-agnostic. Returns true if the pursuer should give up NOW (the caller
-- does clearAggro + drop, so the de-aggro lands on the live controller).
local function evaluate(e, ctrl, player, now)
    local pawn = getPawn(ctrl); if not isValid(pawn) then return end
    local pdead = false; pcall(function() pdead = pawn:IsDead() or pawn:IsDying() end)
    if pdead then return end
    if not e.cls then e.cls = classNameOf(pawn) end
    local ploc = getLoc(player); if not ploc then return end
    local pl = getLoc(pawn)
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local dt = e.lastEval and (now - e.lastEval) or 0

    local d = pl and (math.sqrt(dist2(pl, ploc)) / 100) or -1   -- metres
    local gateM = crouched and (CONFIG.hide_min_distance_m * CONFIG.hide_crouch_mult) or CONFIG.hide_min_distance_m
    local far = d >= 0 and d >= gateM
    local needed = far and CONFIG.hide_seconds or (CONFIG.hide_seconds * CONFIG.hide_close_mult)
    if crouched then needed = needed * CONFIG.hide_crouch_mult end

    -- "Unseen" accumulator: climbs while out of sight, bleeds DOWN while seen (not zeroes),
    -- so a brief glimpse doesn't restart the timer but steady sight keeps a pursuer locked on.
    e.unseen = e.unseen or 0
    local sees = hasLOS(ctrl, player)
    if sees then e.unseen = math.max(0, e.unseen - dt * CONFIG.seen_decay)
    else e.unseen = e.unseen + dt end
    vlog(string.format("hunt %s unseen %.1f/%.1fs d=%.0fm", e.cls or "?", e.unseen, needed, d))
    return e.unseen >= needed
end

-- ---------------------------------------------------------------------------
--  DRIVER: the game's combat tick, fired ~17x/sec on each battling module. `self` is a
--  LIVE module. We filter cheaply (reads of self only), resolve its live controller,
--  evaluate in-context, and hold NOTHING across ticks.
-- ---------------------------------------------------------------------------
local ANNOUNCED = false
local function onBattleTick(self)
    if not CONFIG.hide_enabled then return end
    local player = livePlayer(); if not player then return end    -- you dead/dying: touch nothing
    local module = unwrap(self); if not isValid(module) then return end
    local mid = objId(module); if not mid then return end         -- reads live `self` only: safe
    local now = os.clock()
    local e = TRACK[mid]
    if e then
        e.lastSeen = now
        if (now - (e.lastEval or 0)) < CONFIG.eval_throttle_s then return end   -- throttle: skip the walk
    end
    -- Cheap filters on the LIVE module (reads of `self` only -- no Outer-walk yet):
    local tgt; pcall(function() tgt = module:GetTargetActor() end)
    if not isPlayerActor(tgt) then                                -- not hunting the player (pal-vs-pal / lost target)
        if e then TRACK[mid] = nil end                            -- was ours, isn't now -> forget it
        return
    end
    local inBattle = false; pcall(function() inBattle = module:IsBattleMode() end)
    if not inBattle then return end                              -- finishing/teardown -> do NOT Outer-walk it
    -- Resolve the LIVE controller (module is battling + targeting the player -> its owner is alive):
    vlog("op resolve " .. mid)                                    -- breadcrumb: the ONLY reach past `self`
    local ctrl = resolveController(module); if not isValid(ctrl) then return end
    if not ANNOUNCED then ANNOUNCED = true; log("hide-to-escape: driven by UpdateBattleState (resolve-live)") end
    if not e then e = { unseen = 0 }; TRACK[mid] = e; vlog("track+ " .. mid) end
    e.lastSeen = now
    local giveUp = evaluate(e, ctrl, player, now)
    e.lastEval = now
    if giveUp then clearAggro(ctrl); TRACK[mid] = nil; log("hide-escape: " .. (e.cls or "?") .. " lost you") end
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAICombatModule:UpdateBattleState", function(self) onBattleTick(self) end)
    end)
    log("hide-to-escape: UpdateBattleState hook " .. (ok and "registered" or "FAILED"))
end

-- ---------------------------------------------------------------------------
--  STALENESS GC (pure Lua). Drop TRACK entries whose module stopped ticking -- the pal left
--  combat by ANY route (gave up / died / fled / despawned / you teleported / you died).
--  This touches NO game object: it only compares os.clock timestamps we stored, so a freed
--  pursuer is simply forgotten, never poked. This single loop replaces every teardown hook.
-- ---------------------------------------------------------------------------
if CONFIG.hide_enabled then
    LoopAsync(CONFIG.gc_ms, function()
        local now; pcall(function() now = os.clock() end)
        if now then
            for mid, e in pairs(TRACK) do
                if not e.lastSeen or (now - e.lastSeen) > CONFIG.stale_s then
                    TRACK[mid] = nil; vlog("track- " .. mid .. " (stale)")
                end
            end
        end
        return false
    end)
end

-- ===== DEV STUTTER METER -- BRANCH ONLY, STRIP BEFORE RELEASE ================
-- Detects game-thread hitches independently of our logic: a fast sampler on the game thread;
-- when a frame stalls, the queued sample fires late and the wall-clock gap spikes. Reports
-- worst gap + hitches per ~5s window, plus peakHunters (max pursuers tracked) so we can see
-- whether cost scales with the size of a chase.
local STUTTER = { enabled = true, sample_ms = 50, hitch_ms = 100, window = 100,
                  last = nil, worst = 0, hitches = 0, n = 0, peakHunters = 0, ok = true }
if STUTTER.enabled then
    LoopAsync(STUTTER.sample_ms, function()
        ExecuteInGameThread(function()
            if not STUTTER.ok then return end
            local now; pcall(function() now = os.clock() end)
            if not now then STUTTER.ok = false; log("stutter-meter: os.clock unavailable, disabled"); return end
            now = now * 1000
            local hn = trackCount(); if hn > STUTTER.peakHunters then STUTTER.peakHunters = hn end
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

log("Predators & Stealth runtime v3 loaded (resolve-live). hide-to-escape " .. (CONFIG.hide_enabled and "ON" or "OFF")
    .. " (" .. CONFIG.hide_seconds .. "s no-sight, >" .. CONFIG.hide_min_distance_m .. "m, crouch x" .. CONFIG.hide_crouch_mult .. ").")
