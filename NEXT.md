# NEXT — Predators & Stealth

Ordered. Crash work first, then behavior, then release.

- [ ] **Fix the flying-pal-pack residual crash.** Big CloverFairy pack still trips the
      use-after-free (`0x34d225c`, a UFunction on a freed pursuer). Add per-call breadcrumbs
      inside `evaluate` (`op los` / `op pawn` / `op clear`) so the next clover-pack crash names
      the exact call, then guard/restructure it. Reproduce by pulling a big clover swarm.
- [ ] **Re-confirm normal-pal de-aggro** still fires after the `tpCount`-instead-of-target-class
      change (last session went straight to boss/clovers; didn't watch a clean ground-pal give
      up). Fight wild pals, hide, expect `hide-escape`.
- [ ] **Your-pal-vs-mobs behavior (design):** sick your otomo on wild mobs, then hide/run. Does
      a mob keep fighting your pal or fully disengage? `clearAggro` empties the whole hate map,
      so a mob that also targets you abandons the pal fight when you hide. If that's wrong,
      strip only the player's hate (needs the player InstanceID, not `Empty()`). If a mob
      targets only your pal (`tpCount=0`) we never track it — it keeps fighting your pal.
- [ ] **Hammer big packs** for peak-load stability (partly done — found the clover residual).
- [ ] **Verify boss markers.** Only `Gym` (Grizzbolt/ElecPanda_Gym) confirmed; check other tower
      / raid bosses get detected (`CONFIG.boss_markers`).
- [ ] **Cleanup for release:** strip crash breadcrumbs + stutter meter (marked BRANCH ONLY),
      set `verbose = false`.
- [ ] **Reconcile:** backport the crash-safe design to `main`; commit; CHANGELOG entry; package.

## Later / feature backlog
- [ ] **Flee-at-low-HP:** pursuer retreats at ~10% HP (needs a callable flee/return trigger).
- [ ] **PalModOptions:** optional in-game options (feature-detect; mod still works without it).
- [ ] **Data:** neutral boss mammorest won't auto-aggro (PalSchema `AIResponse`).
- [ ] **Multiplayer:** untested.
