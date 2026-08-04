# STATUS — Predators & Stealth

_Last updated: 2026-08-04. **v2.1.0 shipped.**_

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
No active work item — **v2.1.0 is shipped and uploaded.** The options menu stays size-only by
choice (per-pal tweaking = edit the JSON). See `NEXT.md` for the backlog: the open your-pal-vs-mobs
question, boss-marker + multiplayer verification, and ideas (more menu tunables, level-gap sight,
Mammorest aggro).

## Dev note
The shipped `main.lua` is clean (`verbose = false`, no crash-trace). The crash-trace facility lives
at tag `archive/crash-instrumented-2026-08-04` — recover from there if a crash ever comes back.
