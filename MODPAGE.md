# Predator & Stealth — mod-page copy

Paste/adapt this when you create the Nexus Mods, CurseForge, or Steam Workshop
page. Sections are labeled; most upload forms have separate fields for Summary,
Description, etc.

---

## Name
Predator & Stealth

## Version
1.0.0

## Short summary (one line)
Most wild Pals now hunt you on sight — but crouch, break line of sight, and slip away. A hostile world where stealth actually works.

## Description

The wilds should be dangerous. In vanilla Palworld most wild Pals ignore you or
flee, so you wander the world unbothered. Predator & Stealth flips that: nearly
every wild Pal now **hunts you when it spots you**. A small, curated list of
docile species (Lamball, Cattiva, Chikipi and friends) stays passive — the world
is hostile, with a few gentle exceptions.

But being hunted isn't the whole story — **stealth actually works.** Detection
needs real line of sight (no seeing through walls), reaches farther for Pals a
higher level than you, and **shrinks when you crouch** — which also opens a blind
spot behind you. Break line of sight, put some distance between you and your
pursuer, and after a few seconds it loses the trail and gives up. Sneak past
sleeping Pals. Your own Pals are never turned against you.

Unlike the "make everything hostile" pak mods, this is all done live, per-Pal, at
runtime — which is what makes the stealth, level-scaling, and hide-to-escape
possible instead of a blunt all-or-nothing toggle.

## Why a curated prey list instead of "all hostile"?
A world where *literally everything* — including the passive livestock you farm —
tries to kill you gets tedious fast, and it erases the stealth gameplay (there's
no sneaking past a Chikipi that wants you dead). Keeping a short list of docile
species passive makes the danger feel deliberate, and the list is a plain text
file you can edit to taste.

## Features
- **Aggressive by default.** Wild Pals hunt you in range with line of sight;
  only species in the prey list stay passive.
- **Player-editable `PreyList.txt`** — add or remove passive species freely
  (plain-text checklist, loaded at startup).
- **Line-of-sight detection** — no wall-hacks; duck behind cover and you're unseen.
- **Crouch stealth** — crouching shortens detection range and adds a rear blind spot.
- **Level-scaled awareness** — higher-level Pals notice you from farther (capped).
- **Hide-to-escape** — lose line of sight and distance for a few seconds and
  pursuers give up (works against melee and ranged alike).
- **Skips sleeping Pals** — sneak past them.
- **Never turns your own Pals hostile** — wild Pals only.
- Runs automatically, no keybinds. One lightweight scan on a timer, with a
  per-tick safety cap on how many Pals can be provoked at once.

## Configuration
Open `Scripts/main.lua` and edit the `CONFIG` block at the top:
- `base_range_m` — standing detection range in metres (default `12`).
- `crouch_mult` — detection range multiplier while crouched (default `0.6`).
- `front_half_angle` / `rear_mult` — crouch vision cone; outside the cone
  (behind/sides) detection is multiplied by `rear_mult` (default `0.35`).
- `per_level_bonus` / `level_bonus_cap` — how much a Pal's level advantage
  extends its range, and the cap.
- `hide_seconds` / `hide_min_distance_m` / `hide_crouch_mult` — how long out of
  sight (and how far) before a pursuer gives up; crouching cuts both.
- `require_los`, `skip_sleeping`, `scan_ms`, `max_aggros_per_scan` — core toggles.

Passive species live in `PreyList.txt` next to the `Scripts` folder — one species
id per line, `#` to comment a line out.

## Requirements
- **UE4SS** (RE-UE4SS) installed for Palworld.
- Single-player / client (host-and-play). Dedicated servers untested.

## Installation
1. Install UE4SS for Palworld if you haven't.
2. Extract this download so the `PredatorStealth` folder sits in your UE4SS
   `Mods` folder, e.g.:
   `Palworld\...\ue4ss\Mods\PredatorStealth\`
3. Enable it. Most UE4SS builds auto-enable via the included `enabled.txt`.
   If your setup uses `mods.txt`, add this line:
   `PredatorStealth : 1`
4. Launch the game.

## Compatibility
- PC (Steam) build with UE4SS. **Does not work** on the Xbox / Microsoft Store
  (Game Pass) version or on consoles.
- Don't run it alongside "all Pals hostile" pak mods — they override the same
  behavior and defeat the stealth/curation.
- Plays nice with other UE4SS Lua mods.

## Known minor issue
On a very dense spawn, only a few Pals are provoked per scan tick (a deliberate
safety cap), so a whole crowd may take a second or two to fully turn on you.

## Credits
Created by Xidorian.
