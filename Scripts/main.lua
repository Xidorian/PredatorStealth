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
                local resp = ""; pcall(function() resp = string.lower(tostring(rowData.AIResponse)) end)
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

local function scan()
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

RegisterKeyBind(Key.F8, function() CONFIG.enabled = not CONFIG.enabled; log("Predator & Stealth " .. (CONFIG.enabled and "ENABLED" or "DISABLED")) end)
RegisterKeyBind(Key.F7, function() CONFIG.enabled = false; log("scan PAUSED (F8 to resume). Run a few steps to shake current attackers -- proper de-aggro coming once we find the safe function.") end)

log(string.format("Predator & Stealth v6 loaded [%s]. prey HP<=%d, base %dm, crouch x%.1f, rear x%.2f (cone %d deg). F8 toggle, F7 pause.",
    CONFIG.enabled and "ON" or "OFF", CONFIG.prey_hp_max, CONFIG.base_range_m, CONFIG.crouch_mult, CONFIG.rear_mult, CONFIG.front_half_angle))
