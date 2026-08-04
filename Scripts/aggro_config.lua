-- aggro_config.lua -- Predators & Stealth: shared resolver for the PalModOptions (PMO) tunables menu.
--
-- Single source of truth for (a) locating + reading PMO's persisted .ini, (b) the difficulty
-- PRESETS, and (c) resolving the effective knobs from the player's choices. Both consumers require it:
--   * main.lua          -- overrides its runtime CONFIG (give-up time / distance / crouch, hide on/off).
--   * aggro_options.lua -- uses detect_scale (data) + the size toggles when it regenerates the patch.
--
-- SAFETY: touches NO game objects -- only a ModRef shared variable (for the config dir) + a file read.
-- apply_mode = game_restart means the .ini is already stable on disk at boot, so reading it at load
-- has no race with PMO or PalSchema. Any miss (no PMO / no .ini / bad key) -> Normal-preset defaults,
-- which are exactly the historically shipped hardcoded values -> the mod behaves as before.

local M = {}

local PMO = "PalModOptions.V1."
local ID  = "PredatorStealth"

-- Difficulty presets. Normal == the values main.lua shipped hardcoded. Custom uses the player's
-- individual sliders instead of a row here. Lower give-up/distance/detect = easier to escape; the
-- crouch multiplier scales BOTH the give-up time and distance gate (smaller = crouch helps more).
M.PRESETS = {
    Relaxed  = { hide_seconds = 4, hide_min_distance_m = 12, hide_crouch_mult = 0.4, detect_scale = 0.75 },
    Normal   = { hide_seconds = 6, hide_min_distance_m = 20, hide_crouch_mult = 0.5, detect_scale = 1.00 },
    Hardcore = { hide_seconds = 9, hide_min_distance_m = 30, hide_crouch_mult = 0.7, detect_scale = 1.30 },
}

-- Factory defaults (no PMO / no .ini / missing keys) == Normal preset + hide on + all sizes hostile.
local DEFAULTS = {
    hide_enabled        = true,
    preset              = "Normal",
    hide_seconds        = 6,
    hide_min_distance_m = 20,
    hide_crouch_mult    = 0.5,
    detect_scale        = 1.0,
}

-- ---- locate the .ini: PMO's ConfigDirectory shared var, else a deterministic fallback ----------
-- The fallback needs no PMO to be up (works even if PMO loads after us), so main.lua can read the
-- file reliably at boot -- the whole reason apply_mode is game_restart.
local function scriptDir()
    local s = debug.getinfo(1, "S").source or ""
    s = (s:sub(1, 1) == "@") and s:sub(2) or s
    return s:match("^(.*)[/\\][^/\\]+$") or "."
end
local function sv_get(k) local v; pcall(function() v = ModRef:GetSharedVariable(k) end); return v end

function M.iniPath()
    local dir
    if ModRef ~= nil then dir = sv_get(PMO .. "ConfigDirectory") end
    if type(dir) == "string" and dir ~= "" then return dir .. "\\" .. ID .. ".ini" end
    local scripts = scriptDir()                                              -- .../Mods/PredatorsandStealth/Scripts
    local mods = scripts:match("^(.*)[/\\][^/\\]+[/\\][^/\\]+$") or scripts   -- .../Mods
    return mods .. "/PalModOptions/Scripts/config/" .. ID .. ".ini"
end

-- ---- decode one JSON-encoded .ini value: bool | number | quoted string -------------------------
local function decodeValue(v)
    v = v:match("^(.-)%s*$") or v                      -- trim any trailing whitespace/CR
    if v == "true" then return true end
    if v == "false" then return false end
    local s = v:match('^"(.*)"$'); if s then return s end
    local n = tonumber(v); if n then return n end
    return nil
end

-- ---- read the raw persisted choices (all keys), pre-seeded with defaults ------------------------
function M.readRaw()
    local raw = {}
    for k, v in pairs(DEFAULTS) do raw[k] = v end
    raw.sizes = { XS = true, S = true, M = true, L = true, XL = true }
    local f = io.open(M.iniPath(), "r"); if not f then return raw end
    for line in f:lines() do
        local key, enc = line:match("^([%w_%.%-]+)=(.*)$")                    -- skips the "# ..." comment lines
        if key then
            local val = decodeValue(enc)
            if val ~= nil then
                local tier = key:match("^size_(%w+)$")
                if tier then
                    if raw.sizes[tier] ~= nil then raw.sizes[tier] = (val == true) end
                elseif raw[key] ~= nil then                                   -- only known scalar keys
                    raw[key] = val
                end
            end
        end
    end
    f:close()
    return raw
end

-- ---- resolve effective knobs: the preset drives the 4 tuning knobs unless it is Custom ----------
function M.effective()
    local raw = M.readRaw()
    local eff = {
        hide_enabled = raw.hide_enabled == true,
        preset       = raw.preset,
        sizes        = raw.sizes,
    }
    local p = (raw.preset ~= "Custom") and M.PRESETS[raw.preset] or nil       -- unknown preset -> nil -> sliders
    if p then
        eff.hide_seconds        = p.hide_seconds
        eff.hide_min_distance_m = p.hide_min_distance_m
        eff.hide_crouch_mult    = p.hide_crouch_mult
        eff.detect_scale        = p.detect_scale
    else                                                                     -- Custom: the individual knobs
        -- The knobs persist as enum STRINGS ("6", "0.5", ...); coerce back to numbers, default on miss.
        eff.hide_seconds        = tonumber(raw.hide_seconds)        or DEFAULTS.hide_seconds
        eff.hide_min_distance_m = tonumber(raw.hide_min_distance_m) or DEFAULTS.hide_min_distance_m
        eff.hide_crouch_mult    = tonumber(raw.hide_crouch_mult)    or DEFAULTS.hide_crouch_mult
        eff.detect_scale        = tonumber(raw.detect_scale)        or DEFAULTS.detect_scale
    end
    return eff
end

return M
