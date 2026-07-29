-- ============================================================================
--  Predators & Stealth  v1.0.0  --  Palworld UE4SS Lua mod
--
--  AGGRESSIVE BY DEFAULT. Only species in PreyList.txt (or the built-in PREY
--  fallback below) stay passive -- everything else (including all the vanilla
--  "flee-then-fight" Escape_to_Battle pals) is forced to hunt the player when in
--  range + line-of-sight. Range scales with level gap (capped); crouch shrinks
--  it and adds a rear stealth cone; safety-capped aggros per scan.
--
--  HIDE-TO-ESCAPE: a pursuer that loses line-of-sight to you AND is far enough
--  away for a few seconds gives up (clears its hate map + target list).
--
--  Runs automatically -- no keybinds. Tune via the CONFIG block below and the
--  player-editable PreyList.txt next to this Scripts folder.
-- ============================================================================

local CONFIG = {
    enabled            = true,   -- master on/off switch
    base_range_m       = 12,
    crouch_mult        = 0.6,  -- crouched detection range = base x this (0.6 -> ~7.2m front)
    front_half_angle   = 90,   -- HALF-angle of the vision cone; 90 = a 180-deg front cone.
                               -- CROUCH-ONLY: standing detection is omnidirectional (see below).
    rear_mult          = 0.35, -- when crouched AND outside the cone (behind/sides), range x this
    per_level_bonus    = 0.03,
    level_bonus_cap    = 1.0,
    scan_ms            = 1500,
    max_aggros_per_scan= 4,      -- safety: never force more than this per tick
    require_los        = true,
    skip_sleeping      = true,
    -- HIDE-TO-ESCAPE: a pal hunting you gives up after hide_seconds with no
    -- line-of-sight AND while it's at least hide_min_distance_m away (so a
    -- point-blank pal won't lose you behind a thin obstacle). LOS already stops a
    -- pal firing at you, so one gate covers melee and ranged alike. Crouching cuts
    -- BOTH the required time and the required distance by hide_crouch_mult.
    hide_enabled       = true,
    hide_seconds       = 7,
    hide_min_distance_m = 20,
    hide_crouch_mult   = 0.5,         -- crouching halves both the time AND the distance
    verbose            = false,
}

-- ============================================================================
--  CURATED PREY LIST -- species that STAY PASSIVE (keep vanilla flee/ignore
--  behavior). EVERYTHING NOT LISTED HERE IS AGGRESSIVE. This is the whole point
--  of the mod: hostile world, small docile exceptions.
--
--  Keys are the lowercase species id = className with "BP_" / "_C" stripped
--  (e.g. BP_Boar_C -> boar). Add/remove freely; elemental variants are separate
--  ids (e.g. hedgehog vs hedgehog_ice) -- add each you want passive.
-- ============================================================================
local PREY = {
    -- never-fight in vanilla (AIResponse Escape / Friendly)
    chickenpal = true,  -- Chikipi
    sheepball  = true,  -- Lamball
    mimicdog   = true,  -- Depresso
    dreamdemon = true,  -- Daedream
    carbunclo  = true,
    -- classic small docile livestock/critters
    pinkcat    = true,  -- Cattiva
    cutefox    = true,  -- Vixy
    woolfox    = true,  -- Cremis
    cowpal     = true,  -- Mozzarina
    alpaca     = true,  -- Melpaca
    penguin    = true,  -- Pengullet
}

local function log(m) print("[PDST] " .. m .. "\n") end
local function vlog(m) if CONFIG.verbose then log(m) end end

-- Load the player-editable PreyList.txt (overrides the built-in PREY set above).
-- Any failure (no io lib, file missing, parse error, empty) keeps the built-in
-- defaults so the mod always works. Path is derived from this script's location.
local function modDir()
    local src; pcall(function() src = debug.getinfo(1, "S").source end)
    if src then
        src = src:gsub("^@", "")
        local d = src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$")
        if d then return d end
    end
    if package and package.path then
        local d = package.path:match("([^;]*)[/\\][Ss]cripts[/\\]%?%.lua")
        if d then return d end
    end
    return nil
end
local function loadPreyFile()
    local dir = modDir()
    if not dir then log("PreyList: mod dir unknown; using built-in defaults"); return end
    local path = dir .. "\\PreyList.txt"
    local f; pcall(function() f = io.open(path, "r") end)
    if not f then log("PreyList.txt not readable; using built-in defaults (" .. path .. ")"); return end
    local set, n = {}, 0
    local ok = pcall(function()
        for line in f:lines() do
            local s = line:gsub("^%s+", "")
            if s ~= "" and s:sub(1, 1) ~= "#" then
                local key = s:match("^([%w_]+)")
                if key then set[string.lower(key)] = true; n = n + 1 end
            end
        end
    end)
    pcall(function() f:close() end)
    if not ok then log("PreyList parse error; using built-in defaults"); return end
    if n == 0 then log("PreyList.txt has 0 passive entries; using built-in defaults"); return end
    for k in pairs(PREY) do PREY[k] = nil end
    for k in pairs(set) do PREY[k] = true end
    log("PreyList.txt loaded: " .. n .. " passive species.")
end
pcall(loadPreyFile)
local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end
local function classNameOf(o) local n; pcall(function() n = o:GetClass():GetFName():ToString() end); return n end
local function ctrlName(o) local n; pcall(function() n = o:GetFName():ToString() end); return n or "" end
local function getLoc(a) local v; local ok=pcall(function() v=a:K2_GetActorLocation() end); if ok and v then local x,y,z; pcall(function() x=v.X;y=v.Y;z=v.Z end); if x then return {x=x,y=y,z=z} end end end
local function dist2(a,b) local dx=a.x-b.x;local dy=a.y-b.y;local dz=a.z-b.z;return dx*dx+dy*dy+dz*dz end

-- 1.0 if the player is within the pal's front vision cone, else rear_mult.
-- Only consulted while the player is crouched (standing = omnidirectional).
local function frontFactor(pal, palLoc, ploc)
    local fwd; local ok = pcall(function() fwd = pal:GetActorForwardVector() end)
    if not ok or not fwd then return 1 end
    local fx, fy; pcall(function() fx = fwd.X; fy = fwd.Y end)
    if not fx then return 1 end
    local fl = math.sqrt(fx*fx + fy*fy); if fl == 0 then return 1 end
    local dx, dy = ploc.x - palLoc.x, ploc.y - palLoc.y
    local dl = math.sqrt(dx*dx + dy*dy); if dl == 0 then return 1 end
    local dot = (fx/fl)*(dx/dl) + (fy/fl)*(dy/dl)
    local angle = math.deg(math.acos(math.max(-1, math.min(1, dot))))
    if angle <= CONFIG.front_half_angle then return 1 else return CONFIG.rear_mult end
end

-- species id from a className ("BP_Boar_C" -> "boar"). Caller passes the class
-- name it already resolved, so we don't re-reflect.
local function speciesKey(cls)
    if not cls then return nil end
    return string.lower(cls:gsub("^BP_", ""):gsub("_C$", ""))
end
-- prey = in the curated PREY set. Everything else (incl. unknown/new species,
-- and all the "Escape_to_Battle" flee-then-fight pals) is aggressive.
local function isPrey(cls)
    local k = speciesKey(cls); if not k then return false end
    return PREY[k] == true
end

local function getLevel(actor) local lvl=1; pcall(function() lvl = tonumber(tostring(actor.CharacterParameterComponent:GetLevel())) or 1 end); return lvl end
local function tpCount(ctrl) local n=0; pcall(function() n=ctrl.TargetPlayers:GetArrayNum() end); return n end
local function hasLOS(ctrl, player) local r=false; pcall(function() r = ctrl:LineOfSightTo(player, nil, false) end); return r end
local function isSleeping(ctrl) local r=false; pcall(function() r = ctrl:IsSleeping() end); return r end
-- stable per-instance id (e.g. "BP_Boar_C_2147480781") for cross-tick tracking
local function objId(o) local n; pcall(function() n = o:GetFName():ToString() end); return n end
-- THE de-aggro call: clear hate map + the active target list (see reference §3)
local function clearAggro(ctrl)
    local hs; pcall(function() hs = ctrl:GetHateSystem() end)
    if isValid(hs) then local hm; pcall(function() hm = hs.HateMap end); if hm ~= nil then pcall(function() hm:Empty() end) end end
    pcall(function() ctrl.TargetPlayers:Empty() end)
end

-- hide-to-escape state: id -> consecutive scan ticks a hunter has had NO line-of-sight.
-- Rebuilt every scan and pruned to only currently-present hunters (no stale growth).
local HUNTERS = {}

local function scan()
    if not CONFIG.enabled then return end
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then return end
    local pLevel = getLevel(player)
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local ploc = getLoc(player); if not ploc then return end

    local pals = FindAllOf("PalCharacter"); if not pals then return end
    local hide_ticks = math.max(1, math.floor(CONFIG.hide_seconds * 1000 / CONFIG.scan_ms + 0.5))
    local aggroed = 0
    local seen = {}   -- hunter ids present this tick (for pruning HUNTERS)
    for _, pal in ipairs(pals) do
        if isValid(pal) and pal ~= player then
            local cls = classNameOf(pal)
            if cls and not cls:find("Player") then
                local ctrl; pcall(function() ctrl = pal.Controller end)
                if isValid(ctrl) and ctrlName(ctrl):find("Wild") then
                    local tp = tpCount(ctrl)
                    if tp > 0 then
                        -- HIDE-TO-ESCAPE: this pal is hunting the player.
                        if CONFIG.hide_enabled then
                            local id = objId(pal)
                            if id then
                                seen[id] = true
                                local loc = getLoc(pal)
                                local gateM = crouched and (CONFIG.hide_min_distance_m * CONFIG.hide_crouch_mult) or CONFIG.hide_min_distance_m
                                local minCm2 = (gateM * 100) ^ 2
                                local far = loc and (dist2(loc, ploc) >= minCm2)
                                -- only "lose" you when it CAN'T see you AND you've put distance between you
                                if (not hasLOS(ctrl, player)) and far then
                                    local needed = crouched and math.max(1, math.ceil(hide_ticks * CONFIG.hide_crouch_mult)) or hide_ticks
                                    local n = (HUNTERS[id] or 0) + 1
                                    HUNTERS[id] = n
                                    if n >= needed then
                                        clearAggro(ctrl)                  -- out of sight + far long enough: give up
                                        HUNTERS[id] = nil; seen[id] = nil
                                        log("hide-escape: " .. (cls or "?") .. " lost you")
                                    end
                                else
                                    HUNTERS[id] = 0                       -- sees you, or too close: not losing you
                                end
                            end
                        end
                    elseif not isPrey(cls) and aggroed < CONFIG.max_aggros_per_scan then
                        -- ACQUIRE: not yet hunting, aggressive species -> aggro if in range + LOS
                        local loc = getLoc(pal)
                        local gap = getLevel(pal) - pLevel
                        local bonus = (gap > 0) and math.min(gap * CONFIG.per_level_bonus, CONFIG.level_bonus_cap) or 0
                        local rangeM = CONFIG.base_range_m * (1 + bonus)
                        if crouched then
                            rangeM = rangeM * CONFIG.crouch_mult
                            -- vision cone only matters while crouched: standing = detected from any direction
                            if loc then rangeM = rangeM * frontFactor(pal, loc, ploc) end
                        end
                        local rangeCm = rangeM * 100
                        if loc and dist2(loc, ploc) <= rangeCm * rangeCm then
                            if not (CONFIG.skip_sleeping and isSleeping(ctrl)) then
                                if (not CONFIG.require_los) or hasLOS(ctrl, player) then
                                    pcall(function() ctrl:ForceBattleStartToTarget(player) end)
                                    aggroed = aggroed + 1
                                    vlog("aggro " .. (cls or "?") .. string.format(" (gap %+d, %.0fm%s)", gap, rangeM, crouched and ", crouched" or ""))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- prune trackers for hunters no longer present (despawned / left / de-aggro'd) -> no stale growth
    for id in pairs(HUNTERS) do if not seen[id] then HUNTERS[id] = nil end end
    if aggroed > 0 then vlog("scan aggroed " .. aggroed) end
end

LoopAsync(CONFIG.scan_ms, function()
    ExecuteInGameThread(function() local ok,e=pcall(scan); if not ok then log("scan err " .. tostring(e)) end end)
    return false
end)


local preyCount = 0; for _ in pairs(PREY) do preyCount = preyCount + 1 end
log(string.format("Predators & Stealth v1.0.0 loaded [%s]. AGGRESSIVE by default, %d passive species (edit PreyList.txt). base %dm | crouch x%.1f + %d-deg cone (crouch-only), rear x%.2f | hide %s (%ds no-LOS, >%dm, crouch x%.1f).",
    CONFIG.enabled and "ON" or "OFF", preyCount, CONFIG.base_range_m, CONFIG.crouch_mult, CONFIG.front_half_angle * 2, CONFIG.rear_mult,
    CONFIG.hide_enabled and "ON" or "OFF", CONFIG.hide_seconds, CONFIG.hide_min_distance_m, CONFIG.hide_crouch_mult))
