-- ============================================================================
--  Predator & Stealth  v7  (dev build in AIProbe folder)
--
--  AGGRESSIVE BY DEFAULT. Only species in the curated PREY set (below) stay
--  passive -- everything else (including all the vanilla "flee-then-fight"
--  Escape_to_Battle pals) is forced to hunt the player when in range + LOS.
--  Range scales with level gap (capped); crouch shrinks it; line-of-sight
--  required. Safety-capped aggros per scan.
--
--  Dev keys: F8 enable/disable · F7 pause · F9 nearest-pal info (prints key) ·
--  F6 read HateMap · F2 full de-aggro · F3 hate-only · F4/F5 dead-end tests.
-- ============================================================================

local CONFIG = {
    enabled            = true,   -- diagnostic build: auto-run so the loader logs (safe: no data = no aggro)
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
    verbose            = false,
    monitor            = true,   -- log any pal currently targeting the player (de-aggro study)
}

-- ============================================================================
--  CURATED PREY LIST -- species that STAY PASSIVE (keep vanilla flee/ignore
--  behavior). EVERYTHING NOT LISTED HERE IS AGGRESSIVE. This is the whole point
--  of the mod: hostile world, small docile exceptions.
--
--  Keys are the lowercase species id = className with "BP_" / "_C" stripped
--  (same string F9 now prints as "key="). Add/remove freely; elemental variants
--  are separate ids (e.g. hedgehog vs hedgehog_ice) -- add each you want passive.
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

-- per-species data (HP + AI response). Retries until the table is populated.
local PDATA = nil
local function loadPalData()
    if PDATA ~= nil then return true end
    local dt = StaticFindObject("/Game/Pal/DataTable/Character/DT_PalMonsterParameter.DT_PalMonsterParameter")
    if not isValid(dt) then return false end
    local t, n = {}, 0
    local ok = pcall(function()
        dt:ForEachRow(function(rowName, rowData)
            local key = tostring(rowName)   -- rowName is a plain string here, not userdata
            if key and key ~= "" then
                local hp = 9999; pcall(function() hp = tonumber(tostring(rowData.Hp)) or 9999 end)
                local resp = ""; pcall(function() resp = string.lower(rowData.AIResponse:ToString()) end)  -- FName -> string
                t[string.lower(key)] = { hp = hp, resp = resp }
                n = n + 1
            end
        end)
    end)
    if not ok or n == 0 then return false end   -- don't cache an empty result; retry next scan
    PDATA = t
    log("pal data loaded (" .. n .. " species)")
    return true
end

local function speciesKey(pal)
    local c = classNameOf(pal); if not c then return nil end
    return string.lower(c:gsub("^BP_", ""):gsub("_C$", ""))
end
-- prey = in the curated PREY set. Everything else (incl. unknown/new species,
-- and all the "Escape_to_Battle" flee-then-fight pals) is aggressive.
local function isPrey(pal)
    local k = speciesKey(pal); if not k then return false end
    return PREY[k] == true
end

local function getLevel(actor) local lvl=1; pcall(function() lvl = tonumber(tostring(actor.CharacterParameterComponent:GetLevel())) or 1 end); return lvl end
local function tpCount(ctrl) local n=0; pcall(function() n=ctrl.TargetPlayers:GetArrayNum() end); return n end
local function hasLOS(ctrl, player) local r=false; pcall(function() r = ctrl:LineOfSightTo(player, nil, false) end); return r end
local function isSleeping(ctrl) local r=false; pcall(function() r = ctrl:IsSleeping() end); return r end

-- log the nearest pal actively targeting the player (runs even when paused)
local function monitorTargeting()
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then return end
    local ploc = getLoc(player); if not ploc then return end
    local pals = FindAllOf("PalCharacter"); if not pals then return end
    local best, bd = nil, math.huge
    for _, p in ipairs(pals) do
        if isValid(p) and p ~= player then
            local ctrl; pcall(function() ctrl = p.Controller end)
            if isValid(ctrl) and ctrlName(ctrl):find("Wild") and tpCount(ctrl) > 0 then
                local loc = getLoc(p); if loc then local d = dist2(loc, ploc); if d < bd then bd = d; best = p end end
            end
        end
    end
    if isValid(best) then
        local ctrl; pcall(function() ctrl = best.Controller end)
        log(string.format("MONITOR targeting=%s dist=%.1fm tp=%d los=%s", classNameOf(best) or "?",
            math.sqrt(bd)/100, tpCount(ctrl), tostring(isValid(ctrl) and hasLOS(ctrl, player) or false)))
    end
end

local function scan()
    if CONFIG.monitor then pcall(monitorTargeting) end
    if not CONFIG.enabled then return end
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then return end
    local pLevel = getLevel(player)
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local ploc = getLoc(player); if not ploc then return end

    local pals = FindAllOf("PalCharacter"); if not pals then return end
    local aggroed = 0
    for _, pal in ipairs(pals) do
        if aggroed >= CONFIG.max_aggros_per_scan then break end
        if isValid(pal) and pal ~= player then
            local cls = classNameOf(pal)
            if cls and not cls:find("Player") and not isPrey(pal) then
                local ctrl; pcall(function() ctrl = pal.Controller end)
                if isValid(ctrl) and ctrlName(ctrl):find("Wild") and tpCount(ctrl) == 0 then
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
                                if isValid(ctrl) and isValid(player) then
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
    if aggroed > 0 then vlog("scan aggroed " .. aggroed) end
end

LoopAsync(CONFIG.scan_ms, function()
    ExecuteInGameThread(function() local ok,e=pcall(scan); if not ok then log("scan err " .. tostring(e)) end end)
    return false
end)

-- F9: readout of the nearest pal (distance + how we classify it)
local function info()
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then log("INFO: no player"); return end
    loadPalData()
    local ploc = getLoc(player); if not ploc then return end
    local pLevel = getLevel(player)
    local crouched = false; pcall(function() crouched = player.bIsCrouched end)
    local pals = FindAllOf("PalCharacter"); if not pals then return end
    local nearest, nd = nil, math.huge
    for _, p in ipairs(pals) do
        if isValid(p) and p ~= player and not tostring(classNameOf(p) or ""):find("Player") then
            local loc = getLoc(p); if loc then local d = dist2(loc, ploc); if d < nd then nd = d; nearest = p end end
        end
    end
    if not isValid(nearest) then log("INFO: no pal nearby"); return end
    local distM = math.sqrt(nd) / 100
    local key = speciesKey(nearest); local d = PDATA and PDATA[key]
    local ctrl; pcall(function() ctrl = nearest.Controller end)
    local los = isValid(ctrl) and hasLOS(ctrl, player) or false
    local gap = getLevel(nearest) - pLevel
    local bonus = (gap > 0) and math.min(gap * CONFIG.per_level_bonus, CONFIG.level_bonus_cap) or 0
    local rangeM = CONFIG.base_range_m * (1 + bonus)
    if crouched then
        rangeM = rangeM * CONFIG.crouch_mult
        local nloc = getLoc(nearest); if nloc then rangeM = rangeM * frontFactor(nearest, nloc, ploc) end
    end
    log(string.format("INFO %s  key=%s  dist=%.1fm  prey=%s (hp=%s resp=%s)  crouched=%s  ourAggroRange=%.1fm  LOS=%s",
        classNameOf(nearest) or "?", tostring(key), distM, tostring(isPrey(nearest)),
        d and tostring(d.hp) or "?", d and d.resp or "?", tostring(crouched), rangeM, tostring(los)))
end
RegisterKeyBind(Key.F9, function() local ok,e=pcall(info); if not ok then log("info err "..tostring(e)) end end)

-- F10: dump the nearest wild pal controller's full function list (find a safe de-aggro fn)
local function fnName(x) local n; pcall(function() n = x:GetFName():ToString() end); return n or "?" end
local function dumpCtrl()
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then return end
    local ploc = getLoc(player); if not ploc then return end
    local pals = FindAllOf("PalCharacter"); if not pals then return end
    local nearest, nd = nil, math.huge
    for _, p in ipairs(pals) do
        if isValid(p) and p ~= player and not tostring(classNameOf(p) or ""):find("Player") then
            local loc = getLoc(p); if loc then local d = dist2(loc, ploc); if d < nd then nd = d; nearest = p end end
        end
    end
    if not isValid(nearest) then log("CTRLFN: no pal nearby"); return end
    local ctrl; pcall(function() ctrl = nearest.Controller end)
    if not isValid(ctrl) then log("CTRLFN: no controller"); return end
    log("=== CTRLFN dump: " .. (classNameOf(ctrl) or "?"))
    local ok, cls = pcall(function() return ctrl:GetClass() end)
    local depth = 0
    while ok and isValid(cls) and depth < 15 do
        local cn = fnName(cls)
        pcall(function() cls:ForEachFunction(function(fn) log("CTRLFN|" .. cn .. "|" .. fnName(fn)) end) end)
        local sok, sup = pcall(function() return cls:GetSuperStruct() end)
        if not (sok and isValid(sup)) then break end
        cls = sup; depth = depth + 1
    end
    -- the hate system is where aggro/targets actually live
    local hs; pcall(function() hs = ctrl:GetHateSystem() end)
    if isValid(hs) then
        log("=== HATE dump: " .. (classNameOf(hs) or "?"))
        local hok, hcls = pcall(function() return hs:GetClass() end)
        local d2 = 0
        while hok and isValid(hcls) and d2 < 15 do
            local hcn = fnName(hcls)
            pcall(function() hcls:ForEachFunction(function(fn) log("HATEFN|" .. hcn .. "|" .. fnName(fn)) end) end)
            pcall(function() hcls:ForEachProperty(function(pr) log("HATEPROP|" .. hcn .. "|" .. fnName(pr)) end) end)
            local sok, sup = pcall(function() return hcls:GetSuperStruct() end)
            if not (sok and isValid(sup)) then break end
            hcls = sup; d2 = d2 + 1
        end
        log("HATE dump done")
    else
        log("no hate system resolved")
    end
    log("CTRLFN dump done")
end
RegisterKeyBind(Key.F10, function() local ok,e=pcall(dumpCtrl); if not ok then log("dump err "..tostring(e)) end end)

-- F6: READ the hate map (step 1 of de-aggro plan). SAFE / read-only.
-- Picks the nearest wild pal that is targeting the player (else nearest pal),
-- gets its PalHate, and dumps the HateMap via the real TMap API
-- (Find/Contains/ForEach). Tells us the value type + the actual number so we
-- can write correct mutation tests next.
local function nearestPal(player, ploc, preferTargeting)
    local pals = FindAllOf("PalCharacter"); if not pals then return nil end
    local targeting, td = nil, math.huge
    local nearest, nd = nil, math.huge
    for _, p in ipairs(pals) do
        if isValid(p) and p ~= player and not tostring(classNameOf(p) or ""):find("Player") then
            local loc = getLoc(p)
            if loc then
                local d = dist2(loc, ploc)
                if d < nd then nd = d; nearest = p end
                if preferTargeting then
                    local ctrl; pcall(function() ctrl = p.Controller end)
                    if isValid(ctrl) and ctrlName(ctrl):find("Wild") and tpCount(ctrl) > 0 and d < td then td = d; targeting = p end
                end
            end
        end
    end
    return targeting or nearest
end

-- resolve an FWeakObjectPtr map key -> the actor's class name (else nil)
local function keyActorName(k)
    local a; if pcall(function() a = k:Get() end) and a ~= nil then
        local cn; pcall(function() cn = classNameOf(a) end); return cn or "obj"
    end
    return nil
end
-- describe the hate-value cell (a UScriptStruct). We don't need its fields for
-- de-aggro; just note it's a struct.
local function describeVal(v)
    if type(v) ~= "userdata" then return type(v) .. ":" .. tostring(v) end
    local st; pcall(function() st = v:type() end)
    return "struct(" .. tostring(st or "?") .. ")"
end

local function hateReadout()
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then log("HATE: no player"); return end
    local ploc = getLoc(player); if not ploc then return end
    local pal = nearestPal(player, ploc, true)
    if not isValid(pal) then log("HATE: no pal nearby"); return end
    local ctrl; pcall(function() ctrl = pal.Controller end)
    if not isValid(ctrl) then log("HATE: no controller"); return end
    local hs; pcall(function() hs = ctrl:GetHateSystem() end)
    if not isValid(hs) then log("HATE: no hate system"); return end
    log(string.format("=== HATE readout: pal=%s tp=%d los=%s", classNameOf(pal) or "?",
        tpCount(ctrl), tostring(hasLOS(ctrl, player))))
    local top; pcall(function() top = hs:FindMostHateTarget() end)
    log("  topTarget=" .. (isValid(top) and (classNameOf(top) or "?") or "none"))

    local hm; local okm = pcall(function() hm = hs.HateMap end)
    if not okm or hm == nil then log("  HateMap=<nil> (ok=" .. tostring(okm) .. ")"); return end
    log("  HateMap luatype=" .. type(hm))
    local mtype; if pcall(function() mtype = hm:type() end) and mtype then log("  HateMap:type()=" .. tostring(mtype)) end

    local cont; local okc = pcall(function() cont = hm:Contains(player) end)
    log("  Contains(player)=" .. (okc and tostring(cont) or "ERR"))
    local fv; local okf = pcall(function() fv = hm:Find(player) end)
    log("  Find(player)=" .. (okf and describeVal(fv) or "ERR"))

    local count = 0
    local oke = pcall(function()
        hm:ForEach(function(k, v)
            count = count + 1
            local kn = (type(k) == "userdata") and (keyActorName(k) or "udata") or (type(k) .. ":" .. tostring(k))
            local isPlayer = tostring(kn):find("Player") ~= nil
            log(string.format("  [%d] key=%s%s val=%s", count, tostring(kn), isPlayer and " <-PLAYER" or "", describeVal(v)))
        end)
    end)
    if not oke then log("  ForEach ERR") end
    log(string.format("HATE readout done (%d entries)", count))
end
RegisterKeyBind(Key.F6, function() local ok,e=pcall(hateReadout); if not ok then log("hate err "..tostring(e)) end end)

-- ==== DE-AGGRO EXPERIMENTS (mutation) ====================================
-- Both pause our scan first (so it can't instantly re-aggro), grab the nearest
-- wild pal that is targeting the player, snapshot state, act, then re-snapshot.
local function targetingPal()
    local player = FindFirstOf("PalPlayerCharacter"); if not isValid(player) then return nil end
    local ploc = getLoc(player); if not ploc then return nil, player end
    return nearestPal(player, ploc, true), player
end
-- log topTarget / TargetPlayers count / HateMap entry count
local function hateSnapshot(tag, pal, ctrl, hs)
    local top; pcall(function() top = hs:FindMostHateTarget() end)
    local hm; pcall(function() hm = hs.HateMap end)
    local cnt = 0; if hm ~= nil then pcall(function() hm:ForEach(function() cnt = cnt + 1 end) end) end
    log(string.format("  %s: pal=%s tp=%d top=%s mapCount=%d", tag, classNameOf(pal) or "?",
        tpCount(ctrl), isValid(top) and (classNameOf(top) or "?") or "none", cnt))
end
-- shared setup: pause scan, resolve pal->ctrl->hs. Returns pal,ctrl,hs,player or nil.
local function deaggroSetup(label)
    CONFIG.enabled = false
    local pal, player = targetingPal()
    if not isValid(pal) then log(label .. ": no targeting pal nearby"); return end
    local ctrl; pcall(function() ctrl = pal.Controller end)
    if not isValid(ctrl) then log(label .. ": no controller"); return end
    local hs; pcall(function() hs = ctrl:GetHateSystem() end)
    if not isValid(hs) then log(label .. ": no hate system"); return end
    return pal, ctrl, hs, player
end

-- F4: ChangeHate(player, 0)  -- §7 step 2 (clean retest)
local function tryChangeHateZero()
    local pal, ctrl, hs, player = deaggroSetup("F4")
    if not hs then return end
    log("=== F4 ChangeHate(player,0) ===")
    hateSnapshot("BEFORE", pal, ctrl, hs)
    local ok, e = pcall(function() hs:ChangeHate(player, 0) end)
    log("  ChangeHate -> " .. (ok and "ok" or ("ERR " .. tostring(e))))
    hateSnapshot("AFTER", pal, ctrl, hs)
end
RegisterKeyBind(Key.F4, function() ExecuteInGameThread(function() local ok,e=pcall(tryChangeHateZero); if not ok then log("F4 err "..tostring(e)) end end) end)

-- F5: SetActiveAI(false)  -- deactivate the whole AI (reversible via true)
local function trySetInactive()
    local pal, ctrl, hs = deaggroSetup("F5")
    if not hs then return end
    log("=== F5 SetActiveAI(false) ===")
    hateSnapshot("BEFORE", pal, ctrl, hs)
    local ok, e = pcall(function() ctrl:SetActiveAI(false) end)
    log("  SetActiveAI(false) -> " .. (ok and "ok" or ("ERR " .. tostring(e))))
    hateSnapshot("AFTER", pal, ctrl, hs)
end
RegisterKeyBind(Key.F5, function() ExecuteInGameThread(function() local ok,e=pcall(trySetInactive); if not ok then log("F5 err "..tostring(e)) end end) end)

-- F3: HateMap:Empty()  -- clear the whole hate map (only entry = the player).
-- No key-matching (that's why Find/Contains/Remove-by-key failed on weakptr keys).
local function tryEmptyHate()
    local pal, ctrl, hs = deaggroSetup("F3")
    if not hs then return end
    local hm; pcall(function() hm = hs.HateMap end)
    if hm == nil then log("F3: no HateMap"); return end
    log("=== F3 HateMap:Empty() ===")
    hateSnapshot("BEFORE", pal, ctrl, hs)
    local ok, e = pcall(function() hm:Empty() end)
    log("  Empty() -> " .. (ok and "ok" or ("ERR " .. tostring(e))))
    hateSnapshot("AFTER", pal, ctrl, hs)
end
RegisterKeyBind(Key.F3, function() ExecuteInGameThread(function() local ok,e=pcall(tryEmptyHate); if not ok then log("F3 err "..tostring(e)) end end) end)

-- F2: FULL de-aggro attempt -- clear HateMap AND TargetPlayers. The last test
-- proved the active target is held in TargetPlayers (tp=1) independently of the
-- hate map, so we clear both. TargetPlayers:Empty is the risky container op.
local function tryFullDeaggro()
    local pal, ctrl, hs = deaggroSetup("F2")
    if not hs then return end
    log("=== F2 full de-aggro (HateMap:Empty + TargetPlayers:Empty) ===")
    hateSnapshot("BEFORE", pal, ctrl, hs)
    local hm; pcall(function() hm = hs.HateMap end)
    if hm ~= nil then local okh = pcall(function() hm:Empty() end); log("  HateMap:Empty -> " .. tostring(okh)) end
    local okt, et = pcall(function() ctrl.TargetPlayers:Empty() end)
    log("  TargetPlayers:Empty -> " .. (okt and "ok" or ("ERR " .. tostring(et))))
    hateSnapshot("AFTER", pal, ctrl, hs)
end
RegisterKeyBind(Key.F2, function() ExecuteInGameThread(function() local ok,e=pcall(tryFullDeaggro); if not ok then log("F2 err "..tostring(e)) end end) end)

RegisterKeyBind(Key.F8, function() CONFIG.enabled = not CONFIG.enabled; log("Predator & Stealth " .. (CONFIG.enabled and "ENABLED" or "DISABLED")) end)
-- F7: pause the scan (SAFE). NOTE: ChangeHate(player, -N) does NOT de-aggro --
-- it registers the player as a target (aggro lever, not de-aggro). Real de-aggro
-- is still an open problem (see PALWORLD_MODDING_REFERENCE.md).
RegisterKeyBind(Key.F7, function() CONFIG.enabled = false; log("scan PAUSED (F8 resumes). (F7 no longer touches hate -- ChangeHate-negative backfires.)") end)

local preyCount = 0; for _ in pairs(PREY) do preyCount = preyCount + 1 end
log(string.format("Predator & Stealth v7 loaded [%s]. AGGRESSIVE by default, %d passive species (edit PreyList.txt). base %dm | crouch x%.1f + %d-deg cone (crouch-only), rear x%.2f.",
    CONFIG.enabled and "ON" or "OFF", preyCount, CONFIG.base_range_m, CONFIG.crouch_mult, CONFIG.front_half_angle * 2, CONFIG.rear_mult))
log("  F6=read.  F2=FULL de-aggro(hate+targets)  F3=hate-only  F4=ChangeHate(0)  F5=SetActiveAI(false).")
