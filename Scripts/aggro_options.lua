-- aggro_options.lua -- Predators & Stealth: by-SIZE aggression options via PalModOptions (PMO).
--
-- WHAT: registers a PMO settings page (five size toggles: XS/S/M/L/XL) and, from the player's
-- choices, regenerates the EFFECTIVE aggressive.jsonc that PalSchema loads -- including only pals
-- whose size tier is enabled. Off-tier pals are simply OMITTED -> they revert to vanilla passive.
--
-- WHY THIS SHAPE (the "split", documented per request): UE4SS Lua can't reliably write the raw
-- monster DataTable, so PalSchema stays the applier; our job is only to DECIDE which pals it makes
-- hostile. And because apply_mode is game_restart, we regenerate the file for the NEXT boot -- no
-- live mutation, and no load-order race with PalSchema (the file is already correct when it reads).
-- Fallback path B (static AIResponse + per-pal overrides) is still available: just stop generating
-- this file and hand-edit the template. See STATUS/NEXT.
--
-- SAFETY: this module touches NO game objects -- only files + PMO shared variables. Sizes are baked
-- (pal_sizes.lua, extracted in-game once via GetSize). No PMO installed / no saved config yet ->
-- every tier is on = the shipped all-hostile default.
--
-- DEV: install paths are hardcoded below; generalize (derive from the mod dir) before release.

local SIZES = require("pal_sizes")

local PMO    = "PalModOptions.V1."
local ID     = "PredatorStealth"
local BASE   = "C:/Program Files (x86)/Steam/steamapps/common/Palworld/Mods/NativeMods/UE4SS/Mods"
local TEMPLATE  = BASE .. "/PredatorsandStealth/Scripts/aggressive_template.jsonc"   -- stable, never written
local EFFECTIVE = BASE .. "/PalSchema/mods/PredatorsandStealth/raw/aggressive.jsonc"  -- what PalSchema loads
local FALLBACK_CFG = BASE .. "/PalModOptions/Scripts/config/" .. ID .. ".ini"

local function log(m) print("[PDST-Options] " .. m .. "\n") end
local function sv_get(k) local v; pcall(function() v = ModRef:GetSharedVariable(k) end); return v end
local function sv_set(k, v) return pcall(function() ModRef:SetSharedVariable(k, v) end) end

local function pmoPresent()
    return ModRef ~= nil and sv_get(PMO .. "ApiVersion") ~= nil
end

-- ---- PMO page manifest (5 size booleans, restart-to-apply) --------------------
local MANIFEST = table.concat({
    '{',
      '"api":1,',
      '"id":"', ID, '",',
      '"title":"Predators & Stealth",',
      '"description":"Choose which wild Pals hunt you, by size. Off = that size stays passive. Restart to apply.",',
      '"version":1,',
      '"apply_mode":"game_restart",',
      '"options":[',
        '{"key":"sec_sizes","type":"section","label":"Hostile Pal sizes"},',
        '{"key":"size_XS","type":"boolean","label":"XS Pals hostile","default":true},',
        '{"key":"size_S","type":"boolean","label":"S Pals hostile","default":true},',
        '{"key":"size_M","type":"boolean","label":"M Pals hostile","default":true},',
        '{"key":"size_L","type":"boolean","label":"L Pals hostile","default":true},',
        '{"key":"size_XL","type":"boolean","label":"XL Pals hostile","default":true}',
      ']',
    '}',
})

local function register()
    sv_set(PMO .. "PendingManifest." .. ID, MANIFEST)
    local existing = sv_get(PMO .. "PendingRegistry")
    existing = type(existing) == "string" and existing or ""
    for e in existing:gmatch("[^\r\n]+") do if e == ID then return end end   -- already listed
    sv_set(PMO .. "PendingRegistry", existing == "" and ID or (existing .. "\n" .. ID))
end

-- ---- read the player's toggles from PMO's persisted .ini ----------------------
local function configPath()
    local dir = sv_get(PMO .. "ConfigDirectory")
    if type(dir) == "string" and dir ~= "" then return dir .. "\\" .. ID .. ".ini" end
    return FALLBACK_CFG
end

local function readToggles()
    local t = { XS = true, S = true, M = true, L = true, XL = true }   -- default: all on
    local f = io.open(configPath(), "r"); if not f then return t end
    for line in f:lines() do
        local k, v = line:match("^(size_%w+)=(%a+)")
        if k then local tier = k:sub(6); if t[tier] ~= nil then t[tier] = (v == "true") end end
    end
    f:close()
    return t
end

-- ---- build the effective patch: template filtered to enabled sizes ------------
local function buildEffective(toggles)
    local f = io.open(TEMPLATE, "r"); if not f then return nil, "template missing at " .. TEMPLATE end
    local entries, kept = {}, 0
    for line in f:lines() do
        local key, obj = line:match('^%s*"([%w_]+)"%s*:%s*(%b{})')   -- one species object per line
        if key then
            local sz = SIZES[key]
            if sz and toggles[sz] then
                entries[#entries + 1] = '    "' .. key .. '": ' .. obj
                kept = kept + 1
            end
        end
    end
    f:close()
    -- strict JSON: comma between entries, none after the last
    return '{\n  "DT_PalMonsterParameter": {\n' .. table.concat(entries, ',\n') .. '\n  }\n}\n', kept
end

local function readFile(p) local f = io.open(p, "r"); if not f then return nil end local c = f:read("*a"); f:close(); return c end
local function writeFile(p, c) local f = io.open(p, "w"); if not f then return false end f:write(c); f:flush(); f:close(); return true end

local function sync()
    local toggles = readToggles()
    local content, kept = buildEffective(toggles)
    if not content then log("ERROR: " .. tostring(kept)); return end
    if readFile(EFFECTIVE) ~= content then
        if writeFile(EFFECTIVE, content) then
            log(string.format("regenerated aggressive.jsonc -> %d pals hostile (XS=%s S=%s M=%s L=%s XL=%s). Restart to apply.",
                kept, tostring(toggles.XS), tostring(toggles.S), tostring(toggles.M), tostring(toggles.L), tostring(toggles.XL)))
        else
            log("ERROR: could not write " .. EFFECTIVE)
        end
    end
end

-- ---- boot: wait for PMO (it may load after us), register once, then sync each poll ----
local registered = false
if ModRef == nil then log("no ModRef; options disabled"); return end
LoopAsync(4000, function()
    if not pmoPresent() then return false end                 -- PMO absent/not up yet -> static default stays
    if not registered then register(); registered = true; log("registered PMO page '" .. ID .. "'") end
    pcall(sync)                                                -- catch the player's Apply, regen for next boot
    return false
end)
log("by-size aggression options loaded.")
