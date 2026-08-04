-- aggro_options.lua -- Predators & Stealth: aggression + difficulty options via PalModOptions (PMO).
--
-- WHAT: registers the PMO settings page (hide-to-escape toggle, difficulty preset + custom sliders,
-- and five size toggles: XS/S/M/L/XL) and applies the DATA-side choices: it regenerates the EFFECTIVE
-- aggressive.jsonc that PalSchema loads -- including only pals whose size tier is enabled, with their
-- detection ranges scaled by detect_scale. Off-tier pals are simply OMITTED from the patch -> they
-- revert to VANILLA. This is NOT "made passive": a Pal that attacks you in vanilla still attacks.
-- The RUNTIME knobs (give-up time/distance/crouch, hide on/off) are consumed by main.lua, not here;
-- both sides read the same choices through the shared aggro_config resolver.
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
local SIZES = require("pal_sizes")
local cfg   = require("aggro_config")   -- shared: .ini location + read, difficulty presets, resolve

local PMO = "PalModOptions.V1."
local ID  = "PredatorStealth"

-- Install paths derived at runtime (portable across installs) via the debug.getinfo pattern
-- PalModOptions itself uses: our own Scripts dir, then up two to the UE4SS Mods root.
local function scriptDir()
    local s = debug.getinfo(1, "S").source or ""
    s = (s:sub(1, 1) == "@") and s:sub(2) or s
    return s:match("^(.*)[/\\][^/\\]+$") or "."
end
local SCRIPTS = scriptDir()                                                  -- .../Mods/PredatorsandStealth/Scripts
local MODS    = SCRIPTS:match("^(.*)[/\\][^/\\]+[/\\][^/\\]+$") or SCRIPTS    -- .../Mods
local TEMPLATE     = SCRIPTS .. "/aggressive_template.jsonc"                  -- stable, never written
local EFFECTIVE    = MODS .. "/PalSchema/mods/PredatorsandStealth/raw/aggressive.jsonc"  -- what PalSchema loads

local function log(m) print("[PDST-Options] " .. m .. "\n") end
local function sv_get(k) local v; pcall(function() v = ModRef:GetSharedVariable(k) end); return v end
local function sv_set(k, v) return pcall(function() ModRef:SetSharedVariable(k, v) end) end

local function pmoPresent()
    return ModRef ~= nil and sv_get(PMO .. "ApiVersion") ~= nil
end

-- ---- PMO page manifest: hide toggle + difficulty preset + custom knobs + size toggles --------
-- Every option is a CYCLE-BUTTON (boolean ON/OFF or enum) -- PMO has no slider, and cycle-buttons
-- read cleaner than its text-input boxes. Section headers are dropped (fewer PMO pages); grouping is
-- carried in the labels ("Custom: ..."). The 4 numeric knobs are enums of fixed steps; aggro_config
-- coerces the chosen string back to a number. Value classes: hide on/off + the 4 knobs are RUNTIME
-- (main.lua); detect_scale is also DATA (buildEffective below); sizes are DATA. All restart-to-apply.
-- The 4 "Custom:" knobs are only consulted when Difficulty = Custom (see aggro_config).
local MANIFEST = table.concat({
    '{',
      '"api":1,',
      '"id":"', ID, '",',
      '"title":"Predators & Stealth",',
      '"description":"Choose how wild Pals hunt you: hide-to-escape difficulty, fine tuning, and which sizes are hostile. Restart to apply.",',
      '"version":3,',
      '"apply_mode":"game_restart",',
      '"options":[',
        '{"key":"hide_enabled","type":"boolean","label":"Hide-to-escape enabled","description":"Break line of sight and gain distance to make pursuers give up. Off = they only stop at the vanilla leash range.","default":true},',
        '{"key":"preset","type":"enum","label":"Difficulty","description":"Relaxed = easier to lose pursuers. Hardcore = harder, and Pals see/hear farther. Custom uses the four Custom knobs below.","choices":["Relaxed","Normal","Hardcore","Custom"],"default":"Normal"},',
        '{"key":"hide_seconds","type":"enum","label":"Custom: give-up time (seconds unseen)","description":"How long a pursuer must fail to see you before it gives up.","choices":["3","4","5","6","8","10","12","15","20"],"default":"6"},',
        '{"key":"hide_min_distance_m","type":"enum","label":"Custom: give-up distance (metres)","description":"You must be at least this far away; point-blank never loses you.","choices":["10","15","20","25","30","40","50"],"default":"20"},',
        '{"key":"hide_crouch_mult","type":"enum","label":"Custom: crouch multiplier (lower = crouch helps more)","description":"Scales both the give-up time and distance while crouching.","choices":["0.3","0.4","0.5","0.6","0.7","0.8","1.0"],"default":"0.5"},',
        '{"key":"detect_scale","type":"enum","label":"Custom: detection range scale (x sight and hearing)","description":"Multiplies every hostile Pal\'s aggro sight and hearing range.","choices":["0.5","0.75","1.0","1.25","1.5","2.0"],"default":"1.0"},',
        '{"key":"size_XS","type":"boolean","label":"XS Pals hostile","description":"Off = XS Pals revert to VANILLA (vanilla-hostile ones still attack; not made passive).","default":true},',
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

-- ---- scale a species object's detection ranges (data knob) --------------------
-- detect_scale multiplies ViewingDistance (int in the schema) and HearingRate (float). x1.0 = no-op.
local function scaleDetection(obj, scale)
    if not scale or scale == 1.0 then return obj end
    obj = obj:gsub('("ViewingDistance"%s*:%s*)([%d%.]+)', function(pre, num)
        return pre .. tostring(math.floor(tonumber(num) * scale + 0.5))
    end)
    obj = obj:gsub('("HearingRate"%s*:%s*)([%d%.]+)', function(pre, num)
        return pre .. string.format("%.1f", tonumber(num) * scale)
    end)
    return obj
end

-- ---- build the effective patch: template filtered to enabled sizes, detection scaled ----------
local function buildEffective(sizes, detectScale)
    local f = io.open(TEMPLATE, "r"); if not f then return nil, "template missing at " .. TEMPLATE end
    local entries, kept = {}, 0
    for line in f:lines() do
        local key, obj = line:match('^%s*"([%w_]+)"%s*:%s*(%b{})')   -- one species object per line
        if key then
            local sz = SIZES[key]
            if sz and sizes[sz] then
                entries[#entries + 1] = '    "' .. key .. '": ' .. scaleDetection(obj, detectScale)
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
    local eff = cfg.effective()                                   -- sizes + detect_scale (preset-resolved)
    local s = eff.sizes
    local content, kept = buildEffective(s, eff.detect_scale)
    if not content then log("ERROR: " .. tostring(kept)); return end
    if readFile(EFFECTIVE) ~= content then
        if writeFile(EFFECTIVE, content) then
            log(string.format("regenerated aggressive.jsonc -> %d pals hostile (XS=%s S=%s M=%s L=%s XL=%s, detect x%.2f). Restart to apply.",
                kept, tostring(s.XS), tostring(s.S), tostring(s.M), tostring(s.L), tostring(s.XL), eff.detect_scale))
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
log("  effective = " .. EFFECTIVE)   -- verify path derivation resolved correctly (DEV log)
