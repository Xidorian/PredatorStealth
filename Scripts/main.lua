-- ============================================================================
--  Predator & Stealth  v4  (dev build in AIProbe folder) -- HARDENED after a crash
--
--  Aggressive by default; small docile prey stay passive.
--    prey = base HP <= prey_hp_max  AND  NOT an actively-hostile response
--    (i.e. not Warlike / Kill_All). Covers Friendly / Escape / NotInterested.
--  Range scales with level gap (capped); crouch shrinks it; line-of-sight
--  required. Safety-capped aggros per scan. Starts DISABLED (F8 to enable).
--
--  F8 = enable/disable.   F7 = pause the scan (safe; no array poking).
-- ============================================================================

local CONFIG = {
    enabled            = true,   -- diagnostic build: auto-run so the loader logs (safe: no data = no aggro)
    prey_hp_max        = 110,
    base_range_m       = 12,
    crouch_mult        = 0.4,
    front_half_angle   = 75,   -- within this many degrees of the pal's facing = full range (its vision cone)
    rear_mult          = 0.35, -- detection range multiplier when you're outside the cone (behind/sides)
    per_level_bonus    = 0.03,
    level_bonus_cap    = 1.0,
    scan_ms            = 1500,
    max_aggros_per_scan= 4,      -- safety: never force more than this per tick
    require_los        = true,
    skip_sleeping      = true,
    verbose            = false,
    monitor            = true,   -- log any pal currently targeting the player (de-aggro study)
}

local function log(m) print("[PDST] " .. m .. "\n") end
local function vlog(m) if CONFIG.verbose then log(m) end end
local function isValid(o) return o ~= nil and type(o) == "userdata" and o.IsValid and o:IsValid() end
local function classNameOf(o) local n; pcall(function() n = o:GetClass():GetFName():ToString() end); return n end
local function ctrlName(o) local n; pcall(function() n = o:GetFName():ToString() end); return n or "" end
local function getLoc(a) local v; local ok=pcall(function() v=a:K2_GetActorLocation() end); if ok and v then local x,y,z; pcall(function() x=v.X;y=v.Y;z=v.Z end); if x then return {x=x,y=y,z=z} end end end
local function dist2(a,b) local dx=a.x-b.x;local dy=a.y-b.y;local dz=a.z-b.z;return dx*dx+dy*dy+dz*dz end

-- 1.0 if the player is within the pal's front vision cone, else rear_mult.
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
-- prey = small AND not actively hostile. Unknown species -> not prey (aggressive).
local function isPrey(pal)
    if not PDATA then return true end   -- if data somehow missing, treat as prey (safe: no aggro)
    local k = speciesKey(pal); if not k then return true end
    local d = PDATA[k]; if not d then return false end
    local hostile = d.resp:find("warlike") or d.resp:find("kill")
    return (d.hp <= CONFIG.prey_hp_max) and (hostile == nil)
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
    if not loadPalData() then return end
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
                    if crouched then rangeM = rangeM * CONFIG.crouch_mult end
                    if loc then rangeM = rangeM * frontFactor(pal, loc, ploc) end   -- behind = harder to notice
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
    if crouched then rangeM = rangeM * CONFIG.crouch_mult end
    local nloc = getLoc(nearest); if nloc then rangeM = rangeM * frontFactor(nearest, nloc, ploc) end
    log(string.format("INFO %s  dist=%.1fm  prey=%s (hp=%s resp=%s)  crouched=%s  ourAggroRange=%.1fm  LOS=%s",
        classNameOf(nearest) or "?", distM, tostring(isPrey(nearest)),
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

RegisterKeyBind(Key.F8, function() CONFIG.enabled = not CONFIG.enabled; log("Predator & Stealth " .. (CONFIG.enabled and "ENABLED" or "DISABLED")) end)
-- F7: pause the scan (SAFE). NOTE: ChangeHate(player, -N) does NOT de-aggro --
-- it registers the player as a target (aggro lever, not de-aggro). Real de-aggro
-- is still an open problem (see PALWORLD_MODDING_REFERENCE.md).
RegisterKeyBind(Key.F7, function() CONFIG.enabled = false; log("scan PAUSED (F8 resumes). (F7 no longer touches hate -- ChangeHate-negative backfires.)") end)

log(string.format("Predator & Stealth v6 loaded [%s]. prey HP<=%d, base %dm, crouch x%.1f, rear x%.2f (cone %d deg). F8 toggle, F7 pause.",
    CONFIG.enabled and "ON" or "OFF", CONFIG.prey_hp_max, CONFIG.base_range_m, CONFIG.crouch_mult, CONFIG.rear_mult, CONFIG.front_half_angle))
