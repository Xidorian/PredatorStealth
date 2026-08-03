# STATUS — Predators & Stealth

_Last updated: 2026-08-03._

## Where it's at
Two big things got fixed this session, and the mod is close to a release-prep pass.

**Crashes — believed solved.** The hide-to-escape runtime was crashing the game. Root work:
(1) drive de-aggro off `JudgeReturnCombatStartPosition` (fires only while a pal actively hunts,
silent at give-up) holding no references across frames; (2) a **warm-up gate** so we never touch
a pal until it's proven a stable hunter; and — the surprise — (3) **removing a DEV stutter meter**
that pumped a function onto the game thread every 50 ms. That meter turned out to be the agitator
behind a load-time crash (and likely more): with it gone, a hard session (6 clovers + others,
hiding, de-aggro firing) stayed clean. A flush-safe crash-trace is still armed to catch any
recurrence by exact call. Needs a few more play sessions to fully retire.

**Mounted/gliding aggro — fixed.** Wild pals ignored a mounted or gliding player. Cause: mounted
you read as a higher biological grade (the mount's), and plain `Warlike` pals stand down against a
higher-grade target. Fix was pure data — set every species to `Warlike_Anyway` (attacks regardless
of grade). Confirmed in-game, no on-foot regression.

## Branches / tags
- **`main`** — `f917c28`, pushed. Now carries the crash-safe rewrite (backport done).
- **`feature/mounted-aggro`** — `f605210`, current. The blanket-`Warlike_Anyway` fix; not yet merged.
- **`feature/resolve-live`** — redundant (== the crash work now on `main`); safe to delete.
- **`archive/main-2026-08-03`** — tag, on origin: the pre-crash-fix `main` (`e8ed5c3`) time capsule.

## Next
See `NEXT.md`. Most remaining work is **validation through play** (Alexander tests, reports back),
then a cleanup pass (strip DEV instrumentation, kill the stray PalSchema duplicate), then merge to
`main` and package per `BUILD.md`.

## Dev note
The live `Scripts/main.lua` still has DEV instrumentation — the flush-safe crash-trace breadcrumbs
and `verbose = true` — to keep catching any crash recurrence. Strip before packaging. The stutter
meter was removed (it was the crash suspect) and must be re-added only briefly for a packaging check.
