# NEXT — Predators & Stealth

**v2.1.0 is shipped.** Crash-safety, mounted-aggro, and the by-size options menu are done. What's
left is a feature to grow the menu, plus a small idea backlog. Most gets validated through play —
Alexander tests, reports back.

## To close out the 2.1.0 release
- [ ] **Upload the zips** (manual): `PredatorStealth-2.1.0.zip` → Nexus, `PredatorStealth-Steam-2.1.0.zip`
      → Steam, `workshop-upload/` → Steam Workshop. Paste `MODPAGE.md` as the description.

## Next feature — options menu phase 2
- [ ] **Per-pal overrides on top of the size buckets.** Let players force specific pals on/off
      regardless of their size tier. Can't be 300 flat toggles (PMO's 128/page cap), so design a
      compact form — a named list, or a per-element/genus sub-page. See `AGGRO-OPTIONS.md`.

## Idea backlog (post-2.1.0)
- [ ] **Verify boss markers** beyond `Gym` (Grizzbolt) — tower/raid bosses detected + not-hidden-from.
- [ ] **Multiplayer** — untested (`currentPlayer` = one local `FindFirstOf(PalPlayerCharacter)`).
- [ ] **Level-gap sight scaling (reopened):** `UPalAISensorComponent.SightDistance` is per-instance
      settable after all — the WoW-style "higher-level pals notice you from further" idea is viable
      again if wanted. Optional.
- [ ] **Data:** neutral boss Mammorest won't auto-aggro (needs its own `AIResponse`).

## Watch (through play)
- [ ] **Crash stability** — believed solved; if one ever recurs, recover the crash-trace from tag
      `archive/crash-instrumented-2026-08-04` and re-deploy to catch the exact call.
