# STATUS — Predators & Stealth

_Last updated: 2026-08-02 (end of ~8h crash-hardening session)._

## Where it's at
The **hide-to-escape** runtime (the one Lua piece; aggression is the PalSchema data patch) was
crashing the game every few minutes. It now **survives an 8-hour session** including hiding,
killing pursuers, outrunning packs, teleporting with pals on you, capturing pals, dying, and a
full tower-boss (Grizzbolt) fight **and kill** — zero crash. De-aggro fires correctly and the
boss is correctly un-hideable-from.

**One rare residual remains:** a big pack of **CloverFairy** (flying pals) still trips the same
use-after-free (`0x34d225c`). It's now rare — only under a heavy, fast flying-pal swarm — but
not fixed.

## How it works now
Every crash was one root: calling a UFunction on a pursuer the game had just freed (`isValid()`
can't catch a zombie; `pcall` can't catch a C++ access violation). The fix was to **drive off a
signal that only fires while a pal is actively hunting** and goes silent the instant it gives
up — `UPalAICombatModule_Wild:JudgeReturnCombatStartPosition` — so we're never handed a
teardown-phase pal. We hold **no references** across ticks (state keyed by module name, a
string), and a pure-Lua staleness sweep forgets anyone whose signal stopped — replacing all the
per-teardown prune hooks. Detection is the game's own `LineOfSightTo`; de-aggro clears the hate
map + target list. Bosses are detected by species and de-aggro is paused for their fight (you
can't hide from a boss, and touching one during its scripted fight crashes).

## Branches
- **`feature/resolve-live`** — current, live build (commit `1bc8bea`).
- `feature/perception-piggyback-probe` — committed fallback (the earlier whack-a-mole approach;
  de-aggro works but crashes on teardown races).
- `main` — shipped v2 (idle-stutter fix only); crash fixes **not yet backported**.

## Next
See `NEXT.md`. Headline items: the flying-pal-pack residual crash, re-confirm normal-pal
de-aggro after the recent target-check change, the your-pal-vs-mobs behavior question, then
strip the dev instrumentation and reconcile to `main`.

## Dev note
The live build still has crash breadcrumbs (`op …` log lines), a stutter meter, and
`verbose=true` — all marked to strip before release.
