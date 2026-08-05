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
--  WARM-UP GATE (flying-pack hardening). Even a live-firing signal can hand us a module in a
--  transient state under a heavy, fast flying-pal swarm (spawn churn / teardown flicker), and
--  touching one there is a use-after-free no isValid/pcall can catch. So on first contact we
--  RECORD ONLY -- we touch nothing but `self` -- and don't walk to the controller / pawn until
--  a module has proven it's a STABLE hunter (fired a few times over a fraction of a second).
--  Transient modules go silent and the GC forgets them before we ever touch them.
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
    warmup_fires        = 3,       -- a module must fire JudgeReturn this many times...
    warmup_s            = 0.35,    -- ...AND span at least this long before we touch its controller/pawn. Skips transient spawn/teardown-flicker modules (the flying-pack use-after-free) -- we hold nothing but `self` until a module proves it's a STABLE hunter.
    stale_s             = 3.0,     -- drop a TRACK entry if its signal hasn't fired in this long (pal left combat)
    gc_ms               = 1000,    -- staleness-GC cadence (pure Lua; touches no game objects)
    boss_row_prefixes   = { "GYM_", "RAID_" },  -- DT row-name (CharacterID) prefixes of SCRIPTED-DEFEAT bosses: GYM_ = tower, RAID_ = raid. You can't hide from these AND their defeat teardown crashes if touched. Field alphas (BOSS_*) are deliberately NOT here -- they stay hideable.
    boss_pause_s        = 300,     -- when a boss is seen, pause ALL de-aggro this long -- long enough to ride through the boss's defeat teardown without touching it. Refreshes while the boss is alive.
    verbose             = true,    -- DEV: ON enables the crash-trace + countdown logging. Ship with this OFF.
}

local function log(m) print("[PDST] " .. m .. "\n") end
local function vlog(m) if CONFIG.verbose then log(m) end end

-- Runtime tunables from the PalModOptions menu (difficulty preset / individual sliders), read from
-- PMO's persisted .ini at load via the shared resolver. game_restart apply-mode => the file is
-- already stable, so there's no race. Guarded end-to-end: any failure leaves the hardcoded defaults
-- above (== Normal preset == shipped behaviour). detect_scale is data-side (aggro_options), not here.
do
    local okReq, mod = pcall(require, "aggro_config")
    if okReq and type(mod) == "table" then
        local okEff, e = pcall(mod.effective)                     -- capture BOTH pcall returns (no `and`-chain truncation)
        if okEff and type(e) == "table" then
            CONFIG.hide_enabled        = e.hide_enabled ~= false
            CONFIG.hide_seconds        = tonumber(e.hide_seconds) or CONFIG.hide_seconds
            CONFIG.hide_min_distance_m = tonumber(e.hide_min_distance_m) or CONFIG.hide_min_distance_m
            CONFIG.hide_crouch_mult    = tonumber(e.hide_crouch_mult) or CONFIG.hide_crouch_mult
            log("tunables: preset=" .. tostring(e.preset) .. " hide=" .. tostring(CONFIG.hide_enabled)
                .. " give-up=" .. tostring(CONFIG.hide_seconds) .. "s >" .. tostring(CONFIG.hide_min_distance_m)
                .. "m crouch x" .. tostring(CONFIG.hide_crouch_mult) .. " (detect x" .. tostring(e.detect_scale) .. " is data-side)")
        else
            log("tunables: resolver error -> built-in defaults (Normal)")
        end
    else
        log("tunables: aggro_config unavailable -> built-in defaults (Normal)")
    end
end

-- ===== DEV CRASH TRACE -- BRANCH ONLY, STRIP BEFORE RELEASE ==================
-- UE4SS.log BUFFERS, so on a use-after-free the last breadcrumbs never reach disk. This writes
-- fine-grained "op" breadcrumbs to a DEDICATED file and FLUSHES after every line, so the very last
-- call before a hard crash survives -- naming the exact UFunction + object + isValid state we saw
-- right before touching it. Path derives from the mod's Scripts dir (OS-portable), CWD fallback.
-- Enabled while CONFIG.verbose = true. Strip this whole block + the trace() calls before release.
local TRACE = { on = CONFIG.verbose, f = nil, path = nil }
if TRACE.on then
    local dir = "."
    pcall(function()
        local s = debug.getinfo(1, "S").source or ""
        s = (s:sub(1, 1) == "@") and s:sub(2) or s
        dir = s:match("^(.*)[/\\][^/\\]+$") or "."          -- .../PredatorsandStealth/Scripts
    end)
    for _, p in ipairs({ dir .. "/pdst_crash_trace.log", "pdst_crash_trace.log" }) do
        local fh; local ok = pcall(function() fh = io and io.open(p, "a") end)
        if ok and fh then TRACE.f = fh; TRACE.path = p; break end
    end
    if TRACE.f then pcall(function() TRACE.f:write("\n==== session start ====\n"); TRACE.f:flush() end) end
    log("crash-trace: " .. (TRACE.f and ("flushing to " .. TRACE.path) or "io unavailable -> print() fallback"))
end
local function trace(op, mid, extra)
    if not TRACE.on then return end
    local t; pcall(function() t = os.clock() end)
    local line = string.format("%.4f %s %s%s", t or 0, op, tostring(mid or "?"), extra and (" " .. extra) or "")
    if TRACE.f then pcall(function() TRACE.f:write(line, "\n"); TRACE.f:flush() end)
    else print("[PDST] trace " .. line .. "\n") end
end
-- ===== END DEV CRASH TRACE ===================================================

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

-- TRACK: module-name(string) -> { firstSeen, lastSeen, fires, warm, unseen, lastEval, cls, rowId, ignore }.
-- Plain data only -- never a game-object reference, so nothing here can go stale or crash when
-- read. firstSeen/fires/warm drive the warm-up gate; unseen is set once a module goes warm.
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

-- BOSS GATE. You can't hide from a scripted-defeat boss (GYM_ tower / RAID_ raid), AND its defeat
-- is a teardown that crashes if we touch it. We detect the boss from its ROW NAME (CharacterID --
-- authoritative, NOT a Blueprint class-name guess) during a normal eval (while it's still alive +
-- safe to read) and set BOSS_UNTIL -- a timer that then rides THROUGH the defeat, so onJudgeReturn
-- bails before touching the dying module. Field alphas (BOSS_*) are NOT scripted bosses -- they stay
-- fully hideable. No boss-manager hooks (those fire during teardown and crashed in dispatch).
-- Refreshes while the boss is alive.
local BOSS_UNTIL = nil
local function bossActive(now) return BOSS_UNTIL ~= nil and now < BOSS_UNTIL end

-- Pawn's DT_PalMonsterParameter row name (CharacterID) -- the authoritative species id. Chain:
-- APalCharacter -> CharacterParameterComponent -> GetIndividualParameter() -> GetCharacterID().
-- Called only inside evaluate() (warm, live, alive pawn -- the same safe envelope as classNameOf),
-- pcall-guarded at every hop; returns nil on any miss so the caller just retries next eval.
local function rowIdOf(pawn, mid)
    trace("rowid.comp", mid)                                      -- about to read pawn.CharacterParameterComponent
    local comp; pcall(function() comp = pawn.CharacterParameterComponent end)
    if not isValid(comp) then trace("rowid.nocomp", mid); return nil end
    trace("rowid.getind", mid)                                    -- about to call GetIndividualParameter()
    local ind; pcall(function() ind = comp:GetIndividualParameter() end)
    if not isValid(ind) then trace("rowid.noind", mid); return nil end
    trace("rowid.getid", mid)                                     -- about to call GetCharacterID()
    local fn; pcall(function() fn = ind:GetCharacterID() end)
    if fn == nil then trace("rowid.noid", mid); return nil end
    local s; pcall(function() s = fn:ToString() end)
    trace("rowid.ok", mid, "row=" .. tostring(s))
    return s
end
-- Scripted-defeat boss = row name starts with GYM_ (tower) or RAID_ (raid). Prefix-anchored at
-- position 1, so field alphas (BOSS_*) and everything else read as hideable.
local function isScriptedBoss(rowId)
    if not rowId then return false end
    for _, p in ipairs(CONFIG.boss_row_prefixes) do
        if rowId:sub(1, #p) == p then return true end
    end
    return false
end

-- Give-up evaluation. ctrl is LIVE (resolved from a WARM, stable, actively-fighting module).
local function evaluate(e, ctrl, player, now, mid)
    trace("eval.getpawn", mid, "sp=" .. (e.cls or "?"))
    local pawn = getPawn(ctrl); if not isValid(pawn) then trace("eval.nopawn", mid); return end
    trace("eval.pawndead", mid)
    local pdead = false; pcall(function() pdead = pawn:IsDead() or pawn:IsDying() end)
    if pdead then trace("eval.dead", mid); return end
    if not e.cls then trace("eval.cls", mid); e.cls = classNameOf(pawn) end
    if not e.rowId then e.rowId = rowIdOf(pawn, mid) end          -- authoritative species row name; nil-safe, retries next eval
    if isScriptedBoss(e.rowId) then                               -- GYM_/RAID_ only: pause de-aggro (rides through its defeat), never de-aggro it
        BOSS_UNTIL = now + CONFIG.boss_pause_s
        if not e.bossLogged then e.bossLogged = true; log("scripted boss: " .. e.rowId .. " -> de-aggro PAUSED (no hiding from a tower/raid boss)") end
        return
    end
    trace("eval.body", mid, "sp=" .. (e.cls or "?") .. " row=" .. tostring(e.rowId))
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
    trace("eval.los", mid)                                        -- about to LineOfSightTo (a game call on the controller)
    local sees = hasLOS(ctrl, player)
    trace("eval.los.ok", mid)
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
    local now; pcall(function() now = os.clock() end); if not now then return end
    if bossActive(now) then trace("hook.bossbail"); return end    -- boss fight: pause, touch NOTHING
    local player = livePlayer(); if not player then return end    -- you dead/dying: touch nothing
    local module = unwrap(self); if not isValid(module) then return end
    local mid = objId(module); if not mid then return end
    trace("hook.contact", mid)                                    -- a live hunting module reached us this frame

    -- FIRST CONTACT: record only. We touch NOTHING but `self` (the one object the hook
    -- guarantees is live this frame). A module in a transient spawn/teardown state can fire
    -- JudgeReturn a few times and vanish; recording-only lets the staleness GC forget it
    -- BEFORE we ever walk to its (possibly-freeing) controller -- the flying-pack crash.
    local e = TRACK[mid]
    if not e then TRACK[mid] = { firstSeen = now, lastSeen = now, fires = 1 }; return end
    e.lastSeen = now
    e.fires = (e.fires or 1) + 1
    if e.ignore then return end                                   -- known non-player module: never re-walk

    -- WARM-UP GATE: only now, once this module has proven it's a STABLE hunter (fired
    -- >= warmup_fires across >= warmup_s), do we walk to the controller / touch the pawn.
    if not e.warm then
        if e.fires < CONFIG.warmup_fires or (now - (e.firstSeen or now)) < CONFIG.warmup_s then return end
        e.warm = true; vlog("warm " .. mid)
    end
    if (now - (e.lastEval or 0)) < CONFIG.eval_throttle_s then return end   -- throttle

    -- Ask the CONTROLLER whether it targets a player (tpCount), instead of reading the target
    -- ACTOR's class. That actor is volatile -- in a boss fight the pal targets your OTOMO pal,
    -- which can churn into a freed zombie mid-fight, and reading its class was the crash. The
    -- controller we resolve from the live warm module is safe; its TargetPlayers COUNT is just a number.
    trace("hook.resolve", mid)                                    -- about to Outer-walk to the controller
    local ctrl = resolveController(module)
    if not isValid(ctrl) or tpCount(ctrl) == 0 then              -- targets no player (a pal / nothing) -> not ours
        e.ignore = true; e.lastEval = now                       -- cache so we never re-walk it
        return
    end
    if not ANNOUNCED then ANNOUNCED = true; log("hide-to-escape: driven by JudgeReturnCombatStartPosition") end
    if e.unseen == nil then e.unseen = 0; vlog("track+ " .. mid) end
    local giveUp = evaluate(e, ctrl, player, now, mid)
    e.lastEval = now
    -- DEV: log the row name of every entity our driver actually processes (answers "does the
    -- tutorial Mammorest / field bosses fire this hook?"). One line per module, first eval only.
    if not e.contactLogged then e.contactLogged = true; log("driver contact: row=" .. tostring(e.rowId) .. " cls=" .. (e.cls or "?")) end
    if giveUp then
        trace("hook.clear", mid, "row=" .. tostring(e.rowId))
        clearAggro(ctrl); trace("hook.clear.ok", mid); TRACK[mid] = nil
        log("hide-escape: " .. (e.cls or "?") .. " lost you")
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
            trace("gc.tick", nil, "n=" .. trackCount())           -- pure-Lua sweep; touches no game object
            for mid, e in pairs(TRACK) do
                if not e.lastSeen or (now - e.lastSeen) > CONFIG.stale_s then
                    TRACK[mid] = nil; vlog("track- " .. mid .. " (stale)")
                end
            end
        end
        return false
    end)
end

-- A dev frame-time meter was removed here: it pumped the game thread every 50ms and was a
-- load-time crash suspect, so it must not ship. To measure hitching once before a release,
-- recover it from git (`git show 4f3a1df:Scripts/main.lua`, near the end). It uses trackCount()
-- (kept above for that purpose).

log("Predators & Stealth runtime v3 loaded (judge-return driver). hide-to-escape " .. (CONFIG.hide_enabled and "ON" or "OFF")
    .. " (" .. CONFIG.hide_seconds .. "s no-sight, >" .. CONFIG.hide_min_distance_m .. "m, crouch x" .. CONFIG.hide_crouch_mult .. ").")

-- By-size aggression options (PalModOptions integration). Separate concern, guarded: a failure
-- here must never take down the hide-to-escape runtime above.
local okOpt, errOpt = pcall(require, "aggro_options")
if not okOpt then log("aggro-options module failed to load: " .. tostring(errOpt)) end

-- DEV grade probe (mounted-aggro / BiologicalGrade investigation). TEMPORARY -- remove this require
-- and delete grade_probe.lua before release. Guarded so it can never affect the runtime above.
local okProbe, errProbe = pcall(require, "grade_probe")
if not okProbe then log("grade-probe failed to load: " .. tostring(errProbe)) end
