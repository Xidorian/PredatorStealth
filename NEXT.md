# NEXT — Predators & Stealth

**v2.1.0 is shipped and uploaded.** No active work item — this is the backlog. Most gets validated
through play; Alexander tests and reports back.

## Open question (never resolved)
- [ ] **Your-pal-vs-mobs behavior.** Sic your otomo on a wild mob, then hide/run. De-aggro
      (`clearAggro`) empties the mob's *whole* hate map, so it abandons the fight with your pal too,
      not just you. Decide if that's wanted; if not, clear only the player's hate (needs the player
      InstanceID, not `Empty()`). Needs a play-observation + a call.

## Needs in-game verification
- [ ] **Boss markers beyond `Gym`.** Only Grizzbolt confirmed detected + un-hideable-from; `Raid`/
      `Tower` markers are untested guesses (`CONFIG.boss_markers`).
- [ ] **Multiplayer** — untested (`currentPlayer` = one local `FindFirstOf(PalPlayerCharacter)`).

## Idea backlog (not started)
- [ ] **More option-menu tunables** — PMO is wired now, so exposing hide timing / distance /
      sight+hearing is cheap if wanted. (Per-pal overrides are intentionally NOT in the menu —
      edit the JSON: `aggressive.jsonc` without PMO, or `Scripts/aggressive_template.jsonc` with it.)
- [ ] **Level-gap sight scaling (reopened):** `UPalAISensorComponent.SightDistance` is per-instance
      settable — the "higher-level pals notice you from farther" idea is viable again.
- [ ] **Data:** neutral boss Mammorest won't auto-aggro (needs its own `AIResponse`).

## Watch (through play)
- [ ] **Crash stability** — believed solved; if one recurs, recover the crash-trace from tag
      `archive/crash-instrumented-2026-08-04` and re-deploy to catch the exact call.

_Cut: flee-at-low-HP; per-pal overrides in the options menu (both symptom-patches / scope we chose not to carry)._
