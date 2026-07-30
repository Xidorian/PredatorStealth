# Changelog — Predators & Stealth

## 2.0.0
Rearchitected from a runtime Lua scanner to a **PalSchema data patch** + a tiny
companion script. Same fantasy — hostile world, working stealth — but it now runs
on Palworld's own AI instead of a background scan, which **eliminates the traversal
stutter entirely** and leans on the game's real senses.

**Changed — how it works**
- **Aggression + detection are now data, not a scan.** Every non-prey Pal is set to
  `AIResponse: Warlike` with per-Pal `ViewingDistance` (sight/aggro range) and
  `HearingRate` (hearing range) via PalSchema. The game's native AI does the
  detecting, so there's **no per-tick world scan** — the repeated freezing some
  players hit while moving is gone by construction.
- **Real two-sense stealth, from the engine.** Sight is a vision cone + true line of
  sight (aggro); hearing is omnidirectional and passes through walls (makes a Pal
  turn to look, which can then lead to sight → aggro). **Crouching silences your
  footsteps**, so a crouched player is heard by nothing — only *seen*. Walk upright
  and Pals hear you coming.
- **Level-scaled awareness is now tier-based.** Tougher species get a larger
  `ViewingDistance`, which tracks zone level (the big things in high-level areas
  notice you from farther). Set in the data, no runtime cost.

**Added**
- **Per-Pal senses you can tune** in `aggressive.jsonc`: `AIResponse`,
  `ViewingDistance`, `HearingRate` — sharp-eared species hear far, deaf/heavy ones
  only close. Category comments on every line.
- **PalSchema is now a required dependency.** See the mod page for install order.

**Removed**
- The runtime detection scanner (the stutter source).
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
