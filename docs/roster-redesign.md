# Design note — event-driven roster (traversal-stutter fix)

Status: proposed. Implementation lives on branch `perf/event-driven-roster`.

## Problem

A player on a 3440×1440@120 setup reported hard traversal stutter — the game
freezes briefly and repeatedly whenever they move — that appears the instant the
mod is enabled and vanishes the instant it's disabled (confirmed by toggling
several times). Four other UE4SS mods run alongside with no issue.

## Root cause

`scan()` runs inside a single `ExecuteInGameThread` on a `LoopAsync` timer
(`scan_ms = 1500`). Everything it does blocks the game thread for the full
duration, so the scan's cost is a frame the game can't render. Two per-tick costs
dominate and both scale with how many pals are loaded:

1. `FindAllOf("PalCharacter")` — walks the entire UObject array every tick.
2. `classNameOf(pal)` = `GetClass():GetFName():ToString()` — three reflection
   hops per pal, paid for *every* pal returned, before any filtering.

The correlation with movement is the tell: as the player traverses, the engine
streams in more pals, each scan gets heavier, and the hitch recurs on the scan
interval. At 120 Hz the frame budget is ~8 ms, so even a 10–15 ms scan reads as a
freeze — a 60 Hz / 1080p player might not notice the same mod.

## Investigation findings

- Hooking is enabled in the target install: `HookProcessInternal = 1`,
  `HookUObjectProcessEvent = 1` (UE4SS-settings.ini). This is the mechanism
  `RegisterHook` / `NotifyOnNewObject` need.
- Event hooks on **native** `/Script/Pal.*` classes demonstrably work in this
  install (from the other installed mods):
  - `NotifyOnNewObject("/Script/Pal.PalUserWidgetOverlayUI", …)` — per-spawn
    callback (AutomaticallySkipModCaution).
  - `RegisterHook("/Script/Pal.PalCharacterCameraComponent:OnStartAim", …)` and
    `…PalPlayerCharacter:OnCompleteInitializeParameter` (FirstPerson).
- No on-disk SDK/function dump exists; the game log only records species names,
  and `MemberVariableLayout.ini` is offset overrides only. So the *exact* AI
  decision-function surface (a hookable flee-vs-fight event) is not yet known —
  that would need a fresh UE4SS dump or a runtime probe.

## Chosen approach — event-driven roster

Keep every behavior knob; stop rediscovering the world every tick.

- **Seed once at load:** one `FindAllOf("PalCharacter")` to populate the roster
  (necessary because `NotifyOnNewObject` only fires for objects created *after*
  registration).
- **Maintain by event:** `NotifyOnNewObject` on the pal character class fires once
  per pal as it streams in — exactly the traversal moment. Cache class name +
  prey classification (and lazily the controller) *then*: one reflection per pal,
  ever, instead of N per second.
- **Timer does the math only:** the `LoopAsync` tick iterates the *cached roster*
  — validity-check and prune dead entries, then run the existing range / LOS /
  crouch-cone / hide-to-escape logic. No whole-array walk, no re-reflection.

This removes both dominant costs. One `FindAllOf` at startup replaces one per
tick; per-pal class reflection happens once per pal instead of every tick.

### Preserved unchanged

Range + level-gap scaling, LOS gating, crouch cone + rear falloff, hide-to-escape.
The redesign changes *how we enumerate pals*, not *how we decide aggro*.

### Caveats to handle in implementation

- `NotifyOnNewObject` only fires post-registration → the load-time seed sweep is
  mandatory, not optional.
- The AI controller can attach a beat after the character spawns → resolve
  `pal.Controller` lazily in the timer and cache once valid, don't assume it at
  spawn.
- Roster entries must be validity-checked (`IsValid`) and pruned each tick so
  despawned/streamed-out pals don't accumulate or crash a reflected call.

## Stretch goal (optional, not required for the fix)

Fully event-driven acquisition — hook the actual flee-vs-fight / perception
decision so no acquisition timer is needed at all. Blocked on identifying a
hookable decision event, which needs a UE4SS function dump or a one-shot runtime
probe (logs the Wild controller's real class name + enumerates its hookable
functions). Treat as a separate follow-up; the roster redesign already removes the
stutter.

## Instrumentation

Bake in scan-duration + roster-size timing behind the existing `verbose` flag
(off by default) so the fix can be confirmed with real numbers from the player's
machine rather than by feel.

## Open items

- Four UE4SS crash dumps landed during two days of testing. Possibly unrelated,
  but worth ruling out given `HookProcessInternal` and `ForceBattleStartToTarget`
  are in play. Inspect at least one dump before shipping the redesign.
