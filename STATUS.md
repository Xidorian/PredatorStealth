# STATUS — Predators & Stealth

_Last updated: 2026-08-04. **v2.1.0 shipped; next batch (C+D+E) committed, in live testing.**_

## In testing now (committed to `main`, not yet released)
Batch **C+D+E** from `NEXT.md` is written and committed — awaiting a live play-test before it's
packaged as the next version. **A** (de-aggro drops only the player, not the otomo fight) is the one
remaining task, held until this batch validates.
- **C — field bosses hunt you (data).** The 59 neutral field-alpha rows (`BOSS_*` = Mammorest, King
  Alpaca, etc.) flipped to `Warlike_Anyway` in both `aggressive.jsonc` and the template, with matching
  `pal_sizes.lua` entries so the size filter keeps them.
- **D — boss no-hide gate by identity (code).** `main.lua` now reads the pursuer's real row name
  (`CharacterID`) and freezes only `GYM_*`/`RAID_*` bosses; field alphas stay hideable. No more
  class-name substring guessing.
- **E — difficulty + tunables menu (feature).** New shared `aggro_config.lua` resolver; PMO page gains
  a Difficulty preset (Relaxed/Normal/Hardcore/Custom), custom sliders (give-up time/distance, crouch,
  detection scale), and a hide on/off master toggle. `main.lua` reads runtime knobs at boot;
  `aggro_options.lua` applies detection scale to the regenerated patch.
- **Live-test focus:** the `[PDST] tunables: …` boot banner; the expanded Mod Options page; a field
  alpha now de-aggros on hide; a tower/gym boss still logs `scripted boss: GYM_… -> de-aggro PAUSED`.

## Where it's at
**v2.1.0 is released** — committed to `main`, tagged `v2.1.0`, pushed. Three things landed since
2.0.1:

- **Crashes solved.** The hide-to-escape runtime was crashing the game. Fixed by driving de-aggro
  off `JudgeReturnCombatStartPosition` (holds no references across frames), a **warm-up gate** (never
  touch a pal until it's a proven stable hunter), and — the real agitator — **removing a dev stutter
  meter** that pumped the game thread every 50 ms. Validated over long play incl. massive pulls.
- **Mounted/gliding aggro fixed.** Mounted you read as a higher biological grade, so plain `Warlike`
  pals stood down. Blanketed all species to `Warlike_Anyway` (attacks regardless of grade).
- **By-size options menu (new feature).** With the optional **PalModOptions** (a.k.a. Mod Options
  Framework), an Esc → Mod Options page toggles which wild-pal **sizes** (XS/S/M/L/XL) are hostile.
  Off = that size reverts to **vanilla** (not passive). Restart-to-apply; regenerates the effective
  `aggressive.jsonc` from a stable template + baked size map. Feature-detected; no PMO → all hostile.

## To upload (manual — in repo root)
- `PredatorStealth-2.1.0.zip` → Nexus · `PredatorStealth-Steam-2.1.0.zip` → Steam ·
  `workshop-upload/` → Steam Workshop. Description copy is in `MODPAGE.md`. See `BUILD.md`.

## Branches / tags
- **`main`** — `4061e32`, the v2.1.0 release. Only branch (feature branches folded + deleted).
- Tags: `v2.1.0` (release), `v2.0.1`/`v2.0.0`, `archive/main-2026-08-03` (pre-crashfix main),
  `archive/crash-instrumented-2026-08-04` (the crash-trace build, if a crash ever resurfaces).

## Next
**v2.1.0 is shipped + uploaded.** A fully-scoped next batch is spec'd in `NEXT.md` for a fresh
session: **C** flip the 59 neutral field-boss rows to aggressive (Mammorest et al.), **D** boss-freeze
via the game's tower/raid flags instead of name guesses, **E** a tunables menu (difficulty presets +
give-up time / distance / crouch / detection / hide-toggle) — commit those, then **A** the big one:
de-aggro drops only the player, so a wild pal keeps fighting your otomo when you hide. All findings
(the `PalClassification.csv` DT dump, boss row families, callable flags) are captured in `NEXT.md`.

## Dev note
The shipped `main.lua` is clean (`verbose = false`, no crash-trace). The crash-trace facility lives
at tag `archive/crash-instrumented-2026-08-04` — recover from there if a crash ever comes back.
