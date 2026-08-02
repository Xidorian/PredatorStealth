-- ============================================================================
--  Predators & Stealth -- runtime layer (v3, JUDGE-RETURN DRIVER)
--
--  Aggression + detection is a PalSchema DATA patch. This script is the small RUNTIME the
--  data can't do: HIDE-TO-ESCAPE -- native de-aggro is LEASH-only, so break line of sight +
--  get distance and, after a few seconds, a pursuer gives up.
--
--  THE CRASH, AND WHY THIS DRIVER FIXES IT. Every use-after-free crash came from touching a
--  pursuer while the game was tearing it down. The old driver, UPalAICombatModule:
--  UpdateBattleState, fires the WHOLE combat lifecycle -- including the wind-down/teardown --
--  so it handed us dying pals and even reading them crashed (uncatchable access violation).
--  A signal probe found the fix: UPalAICombatModule_Wild:JudgeReturnCombatStartPosition -- the
--  wild pal's own "should I keep fighting or return home?" check -- fires ONLY while a pal is
--  actively committed to hunting you, and goes SILENT the instant it gives up (measured: it
--  stopped ~3 minutes before the pals stopped even existing). So it never hands us a
--  teardown-phase pal: whenever it fires, `self` (the combat module) and the controller we
--  walk up to are alive and actively fighting. Reading + de-aggroing from here is safe.
--
--  We still hold NO references across ticks: per-pursuer state (TRACK) is keyed by the module
--  NAME (a string), and a pure-Lua staleness GC drops anyone whose signal stopped -- so a pal
--  that gave up / died / despawned / warped is simply forgotten, never poked.
--
--  "Can it see me" = LineOfSightTo (default viewpoint -- the published form that works).
--  Give-up uses an UNSEEN accumulator that climbs out of sight and bleeds DOWN on a glimpse.
-- ============================================================================

local CONFIG = {
    hide_enabled        = true,
    hide_seconds        = 6,       -- seconds effectively-unseen before a FAR pursuer gives up
    hide_close_mult     = 1.25,    -- close pursuers (<min_distance) take a bit longer
    hide_min_distance_m = 20,      -- must be at least this far (point-blank never loses you)
    hide_crouch_mult    = 0.5,     -- crouching shortens BOTH the give-up time and the distance gate
    seen_decay          = 0.5,     -- while a pursuer sees you, the unseen timer bleeds DOWN at this x rate
    eval_throttle_s     = 0.9,     -- per-pursuer: min seconds between resolve+eval (signal fires several x/sec)
    stale_s             = 3.0,     -- drop a TRACK entry if its signal hasn't fired in this long (pal left combat)
    gc_ms               = 1000,    -- staleness-GC cadence (pure Lua; touches no game objects)
    verbose             = true,    -- DEV(branch): countdowns + crash breadcrumbs ("op ..."). Off before release.
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

local function hasLOS(ctrl, player)
    local r = false; pcall(function() r = ctrl:LineOfSightTo(player, nil, false) end); return r
end

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
local function livePlayer()
    local p = currentPlayer(); if not p then return nil end
    local out = false; pcall(function() out = p:IsDead() or p:IsDying() end)
    if out then return nil end
    return p
end

-- TRACK: module-name(string) -> { unseen, lastEval, lastSeen, cls }. Plain data only -- never
-- a game-object reference, so nothing here can go stale or crash when read.
local TRACK = {}
local function trackCount() local n = 0; for _ in pairs(TRACK) do n = n + 1 end; return n end

-- module -> its owning PalAIController, via the Outer chain, matched by class name. Safe here
-- because JudgeReturnCombatStartPosition only fires on a LIVE, actively-fighting module.
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

-- Give-up evaluation. ctrl is LIVE (resolved from a live actively-fighting module).
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

    e.unseen = e.unseen or 0
    local sees = hasLOS(ctrl, player)
    if sees then e.unseen = math.max(0, e.unseen - dt * CONFIG.seen_decay)
    else e.unseen = e.unseen + dt end
    vlog(string.format("hunt %s unseen %.1f/%.1fs d=%.0fm", e.cls or "?", e.unseen, needed, d))
    return e.unseen >= needed
end

-- ---------------------------------------------------------------------------
--  DRIVER: UPalAICombatModule_Wild:JudgeReturnCombatStartPosition -- the wild pal's own
--  "keep fighting or return home?" check. Fires several x/sec ONLY while actively hunting,
--  silent the instant it gives up. self = the LIVE combat module. We read it, resolve its
--  live controller, evaluate + de-aggro, and hold nothing.
-- ---------------------------------------------------------------------------
local ANNOUNCED = false
local function onJudgeReturn(self)
    if not CONFIG.hide_enabled then return end
    local player = livePlayer(); if not player then return end    -- you dead/dying: touch nothing
    local module = unwrap(self); if not isValid(module) then return end
    local mid = objId(module); if not mid then return end
    local now = os.clock()
    local e = TRACK[mid]
    if e then
        e.lastSeen = now
        if (now - (e.lastEval or 0)) < CONFIG.eval_throttle_s then return end   -- throttle
    end
    vlog("op tick " .. mid)
    local tgt; pcall(function() tgt = module:GetTargetActor() end)
    if not isPlayerActor(tgt) then                                -- hunting something else / lost target
        if e then TRACK[mid] = nil end
        return
    end
    vlog("op resolve " .. mid)
    local ctrl = resolveController(module); if not isValid(ctrl) then return end
    if not ANNOUNCED then ANNOUNCED = true; log("hide-to-escape: driven by JudgeReturnCombatStartPosition") end
    if not e then e = { unseen = 0 }; TRACK[mid] = e; vlog("track+ " .. mid) end
    e.lastSeen = now
    vlog("op eval " .. mid)
    local giveUp = evaluate(e, ctrl, player, now)
    e.lastEval = now
    if giveUp then
        vlog("op clear " .. mid)
        clearAggro(ctrl); TRACK[mid] = nil; log("hide-escape: " .. (e.cls or "?") .. " lost you")
    end
end
if CONFIG.hide_enabled then
    local ok = pcall(function()
        RegisterHook("/Script/Pal.PalAICombatModule_Wild:JudgeReturnCombatStartPosition", function(self) onJudgeReturn(self) end)
    end)
    log("hide-to-escape: JudgeReturnCombatStartPosition hook " .. (ok and "registered" or "FAILED"))
end

-- ---------------------------------------------------------------------------
--  STALENESS GC (pure Lua). Drop TRACK entries whose signal stopped -- the pal left combat by
--  ANY route (gave up / died / fled / despawned / you teleported / you died). Touches NO game
--  object; only compares stored os.clock stamps. This is the whole teardown-safety net.
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

log("Predators & Stealth runtime v3 loaded (judge-return driver). hide-to-escape " .. (CONFIG.hide_enabled and "ON" or "OFF")
    .. " (" .. CONFIG.hide_seconds .. "s no-sight, >" .. CONFIG.hide_min_distance_m .. "m, crouch x" .. CONFIG.hide_crouch_mult .. ").")
