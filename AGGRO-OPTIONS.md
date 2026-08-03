# By-size aggression options — design

Lets players choose **which wild Pals hunt them, by size tier** (XS/S/M/L/XL), from an in-game
menu (PalModOptions → Esc → Mod Options). Restart-to-apply.

## How it works (the current "split" path)

```
PMO menu (5 size toggles)  ──writes──▶  <PalModOptions>/Scripts/config/PredatorStealth.ini
                                                    │  (key=value, persisted)
   aggro_options.lua  ──reads .ini + baked sizes──┘
        │  filters the TEMPLATE to only the enabled sizes
        ▼
   PalSchema/mods/PredatorsandStealth/raw/aggressive.jsonc   ← the EFFECTIVE file PalSchema loads
        │
        ▼  (next game boot)
   PalSchema patches DT_PalMonsterParameter → those Pals are Warlike_Anyway; the rest are omitted → vanilla passive
```

**Files (all in the `PredatorsandStealth` UE4SS mod's `Scripts/`):**
- `pal_sizes.lua` — baked species→size map (`EPalSizeType`), extracted once in-game via
  `UPalDatabaseCharacterParameter:GetSize` (raw data in `palschema/pal-sizes.tsv`). Regenerate with
  the size probe if a game update adds/renames pals.
- `aggressive_template.jsonc` — the **stable, full** list (all 324 species with `AIResponse` +
  sight/hearing). The applier reads this and never writes it. Edit *this* to retune sight/hearing.
- `aggro_options.lua` — registers the PMO page and regenerates the effective `aggressive.jsonc`
  by filtering the template to the enabled size tiers. `require`d from `main.lua` (guarded).

**Why this shape:** UE4SS Lua can't reliably write the raw monster DataTable, so PalSchema stays the
applier; our code only *decides* which Pals it makes hostile. And because `apply_mode = game_restart`,
we regenerate the file for the **next** boot — no live mutation, no load-order race with PalSchema.

**Ownership / the "split":** the applier OWNS `AIResponse` (by including/omitting a species). The
template's `ViewingDistance`/`HearingRate` ride along unchanged. Off-tier species are omitted entirely
(→ passive), per the patch convention "prey = absent from the file".

**Fallback (no PalModOptions installed, or no saved config yet):** every tier defaults on → the
effective file = the full template = today's all-hostile behavior. The mod works standalone.

## Falling back to path B (static + per-pal overrides)

If the by-size menu proves annoying, revert to a static patch with per-pal exceptions:
1. Stop generating the effective file — remove the `require "aggro_options"` line in `main.lua`
   (or gate it off), so nothing overwrites `raw/aggressive.jsonc`.
2. Ship `aggressive_template.jsonc`'s contents directly as `raw/aggressive.jsonc` (static, all hostile),
   and hand-edit per-pal (`AIResponse` per species, or delete a line to make it passive).
3. The size map + PMO page can stay dormant or be removed. Git history holds the wiring either way.

## Phase 2 (not built)
Per-pal overrides layered on top of the size buckets — a small named list (file or a compact menu
section), since 300+ individual toggles exceed PMO's 128-option/page cap.
