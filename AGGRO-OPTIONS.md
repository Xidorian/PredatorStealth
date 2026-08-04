# Aggression & difficulty options — design

Lets players tune the mod from an in-game menu (PalModOptions → Esc → Mod Options), restart-to-apply:
- **Which wild Pals hunt them, by size tier** (XS/S/M/L/XL).
- **How hard Pals are to escape** — a **Difficulty** preset (Relaxed / Normal / Hardcore / Custom)
  plus, under Custom, individual knobs: give-up time, give-up distance, crouch effectiveness, and a
  detection-range scale. A master **Hide-to-escape** on/off switch sits above it.

## The runtime-vs-data split (why two consumers, one resolver)

The menu's choices fall into two kinds, applied in two different places:

| Choice | Kind | Applied by |
|---|---|---|
| give-up time / distance, crouch multiplier, hide on/off | **runtime** | `main.lua` overrides its `CONFIG` at load |
| detection-range scale | **data** | `aggro_options.lua` scales sight/hearing when it regenerates the patch |
| size toggles | **data** | `aggro_options.lua` includes/omits species by tier |

Both sides read the *same* persisted choices through one shared resolver, **`aggro_config.lua`**, so
the preset→values table and the `.ini` reader live in exactly one place.

## How it works (the "split" path)

```
PMO menu  ──writes──▶  <PalModOptions>/Scripts/config/PredatorStealth.ini   (key=<json>, persisted)
                                   │
             aggro_config.lua  ────┤  reads the .ini, applies the difficulty preset (or Custom sliders),
             (shared resolver) ────┘  returns the effective knobs {hide_enabled, give-up time/dist/crouch,
                                   │   detect_scale, sizes{}}
                 ┌─────────────────┴───────────────────┐
                 ▼                                       ▼
   main.lua overrides CONFIG              aggro_options.lua filters the TEMPLATE to enabled sizes,
   (runtime: give-up, crouch,            scales ViewingDistance/HearingRate by detect_scale, and writes
    hide on/off)                         PalSchema/mods/PredatorsandStealth/raw/aggressive.jsonc
                                                         │
                                                         ▼  (next game boot)
                          PalSchema patches DT_PalMonsterParameter → enabled Pals are Warlike_Anyway
                          (with scaled detection); omitted ones revert to VANILLA (a vanilla-hostile
                          Pal still attacks). main.lua reads the same .ini at boot for the runtime knobs.
```

Everything is restart-to-apply (`apply_mode = game_restart`), so the `.ini` is already stable when
both `main.lua` and PalSchema read at boot — no live mutation, no load-order race.

**Files (all in the `PredatorsandStealth` UE4SS mod's `Scripts/`):**
- `pal_sizes.lua` — baked species→size map (`EPalSizeType`), extracted once in-game via
  `UPalDatabaseCharacterParameter:GetSize` (raw data in `palschema/pal-sizes.tsv`). Regenerate with
  the size probe if a game update adds/renames pals.
- `aggressive_template.jsonc` — the **stable, full** list (all 383 species, incl. the 59 field
  bosses, with `AIResponse` + sight/hearing). The applier reads this and never writes it. Edit *this*
  to retune sight/hearing.
- `aggro_config.lua` — the **shared resolver**: locates + reads PMO's `.ini`, holds the difficulty
  `PRESETS` table, and returns the effective knobs (preset drives them unless Custom). `require`d by
  **both** `main.lua` (runtime knobs) and `aggro_options.lua` (data knobs) — one source of truth.
- `aggro_options.lua` — registers the PMO page and regenerates the effective `aggressive.jsonc` by
  filtering the template to the enabled size tiers and scaling detection by `detect_scale`. `require`d
  from `main.lua` (guarded).

**Why this shape:** UE4SS Lua can't reliably write the raw monster DataTable, so PalSchema stays the
applier; our code only *decides* which Pals it makes hostile. And because `apply_mode = game_restart`,
we regenerate the file for the **next** boot — no live mutation, no load-order race with PalSchema.

**Ownership / the "split":** the applier OWNS `AIResponse` (by including/omitting a species). The
template's `ViewingDistance`/`HearingRate` ride along unchanged. Off-tier species are omitted entirely,
so they **revert to vanilla behaviour** (per the patch convention "absent from the file = vanilla"). This
is not the same as passive: a species that is hostile in the base game keeps attacking when its tier is off.

**Fallback (no PalModOptions installed, or no saved config yet):** every tier defaults on → the
effective file = the full template = today's all-hostile behavior. The mod works standalone.

## Falling back to path B (static + per-pal overrides)

If the by-size menu proves annoying, revert to a static patch with per-pal exceptions:
1. Stop generating the effective file — remove the `require "aggro_options"` line in `main.lua`
   (or gate it off), so nothing overwrites `raw/aggressive.jsonc`.
2. Ship `aggressive_template.jsonc`'s contents directly as `raw/aggressive.jsonc` (static, all hostile),
   and hand-edit per-pal (`AIResponse` per species, or delete a line to revert that Pal to vanilla).
3. The size map + PMO page can stay dormant or be removed. Git history holds the wiring either way.

## Phase 2 (not built)
Per-pal overrides layered on top of the size buckets — a small named list (file or a compact menu
section), since 300+ individual toggles exceed PMO's 128-option/page cap.
