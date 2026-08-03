# Changelog, Predators & Stealth

## Unreleased (in testing)

**Fixed**
- **The mod could crash the game during some fights.** Hide-to-escape occasionally
  touched a pursuing Pal's AI the instant the game was tearing it down (on death,
  flee, despawn, teleport, or a boss's scripted defeat) — a use-after-free the engine
  can't recover from. Rebuilt the internals to be crash-safe: the runtime now drives
  off a signal that only fires while a Pal is *actively* hunting you (never during
  teardown), holds no references to Pals between frames, and forgets a pursuer the
  moment it leaves the fight. Bosses are recognised and left alone (you can't hide
  from a scripted boss anyway). A final hardening pass ignores Pals that only flicker
  into a fight for a fraction of a second — the case that survived under big, fast
  flying-Pal swarms. Hide-to-escape behaviour is unchanged.
- **Periodic traversal stutter from the hide-to-escape tick.** The runtime pushed
  work onto the game thread *every* tick — an `ExecuteInGameThread` sync plus a
  `FindFirstOf` scan over every UObject — even when nothing was hunting you, which
  is the vast majority of playtime. That constant per-tick game-thread hit was the
  hitch commenters reported (its rhythm tracked `tick_ms`). The tick now stays fully
  off-thread until a Pal is actually hunting you: the async loop just checks a live
  counter and returns. The player pawn is also cached and only re-fetched on
  death/respawn, so the `FindFirstOf` scan no longer runs per tick even mid-chase.
  Hide-to-escape behaviour is unchanged.

## 2.0.1

**Fixed**
- **Hide-to-escape never fired.** The runtime tick called an undefined `classNameOf`
  helper (added for verbose logging) the moment a Pal was actively hunting, so every
  tick errored out *before* the de-aggro check ran. Pursuers never cleared their hate,
  which read in-game as Pals fighting to the death or searching around forever after
  losing sight. Defined the helper; de-aggro runs again.

**Changed**
- **Faster give-up after breaking line of sight.** Was 7s far / 14s close, the close
  timer felt endless. Now **4s far / 6s close**, with the close multiplier (`hide_close_mult`)
  a real config knob instead of a hardcoded `×2`.
- **86 Pals that refused to attack now do.** Every species whose *vanilla* `AIResponse`
  is `Escape_to_Battle` (Foxparks, Celaray, Deer, and 83 more) ignores a flip to plain
  `Warlike` — it stays stuck in a flee/investigate loop and never commits to an attack.
  Switched those 86 to **`Warlike_Anyway`**, which overrides the escape state; they now
  aggro and attack (and de-aggro via hide-to-escape) correctly. `NotInterested`/`Escape`
  baselines still use plain `Warlike`. Removed a stray duplicate patch file from the
  install that risked a double-load.

## 2.0.0
Rearchitected from a runtime Lua scanner to a **PalSchema data patch** + a tiny
companion script. Same fantasy, hostile world, working stealth, but it now runs
on Palworld's own AI instead of a background scan, which **eliminates the traversal
stutter entirely** and leans on the game's real senses.

**Changed, how it works**
- **Aggression + detection are now data, not a scan.** Every non-prey Pal is set to
  `AIResponse: Warlike` with per-Pal `ViewingDistance` (sight/aggro range) and
  `HearingRate` (hearing range) via PalSchema. The game's native AI does the
  detecting, so there's **no per-tick world scan**, the repeated freezing some
  players hit while moving is gone by construction.
- **Real two-sense stealth, from the engine.** Sight is a vision cone + true line of
  sight (aggro); hearing is omnidirectional and passes through walls (makes a Pal
  turn to look, which can then lead to sight → aggro). **Crouching silences your
  footsteps**, so a crouched player is heard by nothing, only *seen*. Walk upright
  and Pals hear you coming.

**Added**
- **Per-Pal senses you can tune** in `aggressive.jsonc`: `AIResponse`,
  `ViewingDistance`, `HearingRate`, sharp-eared species hear far, deaf/heavy ones
  only close. Category comments on every line.
- **PalSchema is now a required dependency.** See the mod page for install order.

**Removed**
- The runtime detection scanner (the stutter source).
- **Level-scaled awareness** (a 1.0.0 feature). Widening a Pal's detection by how far
  it out-levels you needs a per-frame proximity scan comparing levels, exactly the
  stutter this release removes, and a Pal's sight range is per-*species* data, not a
  per-Pal value we can adjust live. So it can't be done cheaply and is dropped for now;
  detection range is a flat 25 m. May return later as an optional add-on.
- `PreyList.txt`. Prey are now simply the species **absent** from the data patch;
  edit `aggressive.jsonc` to make any Pal passive (delete its line / set `Friendly`)
  or hostile (add it).

**Kept**
- **Hide-to-escape**, rebuilt event-driven: it hooks the moment a Pal targets you,
  watches only your active pursuers (no scan), and clears their hate + target once
  you break line of sight and distance long enough (crouching cuts both).

## 1.0.0
Initial release.

- Aggressive-by-default: every wild Pal hunts the player on sight except a curated
  passive **PreyList** (player-editable `PreyList.txt`).
- Line-of-sight-gated detection; range scales with level gap (capped).
- Crouch shrinks detection range and opens a rear stealth blind spot.
- Hide-to-escape: a pursuer that loses line of sight and gains distance for a few
  seconds gives up (clears its hate map + target list).
