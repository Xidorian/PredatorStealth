# NEXT — Predators & Stealth

Core problems look solved. Remaining "now" work is mostly **validation through play** —
Alexander drives that and reports back. Then release prep, then the idea backlog.

## Now — validate through play (Alexander tests, reports back)
- [ ] **Crash stability.** Believed fixed: removing the DEV stutter meter (a per-50ms
      `ExecuteInGameThread` game-thread pump — the load-tick crash suspect) plus the warm-up
      gate. One solid session stayed clean through 6 clovers + de-aggro. Keep hammering the
      hard cases — big/fast flying-pal swarms, boss fights, teleport/capture/death. The
      flush-safe crash-trace is still armed: if it ever dies again, `pdst_crash_trace.log`
      (next to the live script) names the exact call. Retire once several sessions stay clean.
- [ ] **De-aggro sanity.** `hide-escape` confirmed firing (Deer / CloverFairy / LeafMomonga
      "lost you"). Just keep an eye that ordinary ground pals still give up cleanly.
- [ ] **Your-pal-vs-mobs behaviour (design call).** Sic your otomo on wild mobs, then hide/run.
      `clearAggro` empties the *whole* hate map, so a mob also targeting you abandons the pal
      fight when you hide. If that's wrong, strip only the player's hate (needs the player
      InstanceID, not `Empty()`). A mob targeting only your pal (`tpCount=0`) is never tracked —
      it keeps fighting your pal.
- [ ] **Boss markers.** Only `Gym` (Grizzbolt/ElecPanda_Gym) confirmed; watch that tower/raid
      bosses are detected and correctly not-hidden-from (`CONFIG.boss_markers`).

## Before release (cleanup + package)
- [ ] **Strip DEV instrumentation** from `Scripts/main.lua`: the crash-trace facility
      (`TRACE`/`trace()` + all the `op`/`walk`/`getpawn`/`los` breadcrumbs) and set
      `verbose = false`.
- [ ] **Stutter check, then strip.** Re-add the stutter meter for ONE packaging measurement,
      confirm clean, then remove it again — it must NOT ship (recover from
      `git show 4f3a1df:Scripts/main.lua`).
- [ ] **Delete the stray PalSchema duplicate** from the install:
      `…/PalSchema/mods/PredatorsandStealth/mods/PredatorStealth/raw/aggressive.jsonc`
      (double-load footgun). Ship only the one `…/PredatorsandStealth/raw/aggressive.jsonc`.
- [ ] **Merge + package.** `feature/mounted-aggro` → `main`; delete the now-redundant
      `feature/resolve-live`; roll `## Unreleased` into a version heading; package per `BUILD.md`.

## After everything's fixed — idea backlog
- [ ] **PalModOptions:** optional in-game tunables (feature-detect; mod still works without it) —
      hide_seconds / distance / crouch / per-species sight+hearing.
- [ ] **Data:** neutral boss Mammorest won't auto-aggro (needs its own `AIResponse`).
- [ ] **Multiplayer:** untested (`currentPlayer` = one local `FindFirstOf(PalPlayerCharacter)`).
- [ ] **Level-gap sight scaling (reopened):** `UPalAISensorComponent.SightDistance` is
      per-instance settable after all — the WoW-style "higher-level pals notice you from further"
      idea is viable again if we want it. Optional.
