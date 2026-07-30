# Predators & Stealth — mod-page copy

Paste/adapt this when you create the Nexus Mods, CurseForge, or Steam Workshop
page. Sections are labeled; most upload forms have separate fields for Summary,
Description, etc.

---

## Name
Predators & Stealth

## Version
2.0.0

## Short summary (one line)
Nearly every wild Pal now hunts you — but they hunt with real *senses*. Stay out of sight, keep quiet, crouch, and slip away. A hostile world where stealth actually works.

## Description

The wilds should be dangerous. In vanilla Palworld most wild Pals ignore you or
flee, so you wander the world unbothered. Predators & Stealth flips that: nearly
every wild Pal now **hunts you**. A small curated list of docile species (Lamball,
Cattiva, Chikipi and friends) stays passive — the world is hostile, with a few
gentle exceptions.

But being hunted isn't the whole story — **stealth actually works**, and it works
through the game's *own* senses:

- **They see you.** Sight has a real vision cone and true line of sight (no seeing
  through walls). Get behind cover or out of their cone and you're unseen.
- **They hear you.** Move around and nearby Pals hear you and turn to look — from
  any direction, even through walls. Sharp-eared species (bats, canines, birds)
  hear you from much farther; heavy, deaf ones only up close.
- **Crouch to go silent.** Crouching cuts your noise to nothing — so a Pal won't
  *hear* you, only *see* you. Crouch-sneak behind a Pal and past it; walk upright
  and it'll hear you coming.
- **Hide to escape.** Once something is chasing you, break its line of sight and
  put distance between you, and after a few seconds it loses the trail and gives
  up. Crouching makes it give up sooner.

Your own Pals are never turned against you.

**How it's built (and why it's light):** v2.0.0 drives all the aggression and
detection through Palworld's native AI as a **data patch** — no constant
background scanning, so there's no traversal stutter and it's friendly to lower-end
machines. A tiny companion script adds the one thing the data can't: giving up the
chase when you break line of sight.

**Note — no level-scaled aggro (yet).** v1 made higher-level Pals notice you from
farther. Doing that properly means checking every nearby Pal's level against yours
many times a second — which is exactly the background scanning that caused v1's
stutter — and a Pal's sight range is fixed per species, not a per-Pal value we can
nudge on the fly. So true level-based awareness can't be done without bringing the
lag back, and it's **left out for now** in favor of a smooth, hostile world. It may
return later as an optional add-on.

## Requirements
- **UE4SS** (RE-UE4SS) for Palworld.
- **PalSchema** (by Oak) — **required.** The aggression/detection is a PalSchema
  data patch. Install PalSchema first: https://www.nexusmods.com/palworld (search
  "PalSchema") or its Steam Workshop page.
- Single-player / client (host-and-play). Dedicated servers untested.

## Installation
1. Install **UE4SS** and **PalSchema** for Palworld if you haven't.
2. **Extract this zip into your UE4SS `Mods` folder.** It drops in two things:
   - `Mods\PredatorStealth\` — the mod itself (the hide-to-escape script).
   - `Mods\PalSchema\mods\PredatorStealth\` — the aggression data patch (merges
     into your existing PalSchema install; it won't touch PalSchema's own files).
3. Enable the mod: the included `enabled.txt` auto-enables it on standard RE-UE4SS;
   on the Steam-Workshop UE4SS build add `PredatorStealth : 1` to `Mods\mods.txt`.
4. Launch the game. (Fully restart after any edit to the data patch.)

## Customizing which Pals are hostile / how they sense you
Everything lives in **`PalSchema\mods\PredatorStealth\raw\aggressive.jsonc`** —
one line per Pal, editable in any text editor:
- **Make a Pal passive:** delete its line (it reverts to vanilla), or set its
  `AIResponse` to `Friendly`.
- **Make a passive Pal hostile:** add a line for it with `AIResponse: Warlike`.
- **Aggro range:** `ViewingDistance` (metres) — how far it can *see* you.
- **Hearing range:** `HearingRate` (metres) — how far it *hears* you (crouch
  silences you regardless). Bump it for sharp-eared species, drop it for deaf ones.
- The file header lists every option, and each line is tagged with its category.

The "prey" that stay passive are simply the species **not** in that file (Lamball,
Cattiva, Chikipi, Vixy, Melpaca, Pengullet, and friends).

Hide-to-escape timing is in `PredatorStealth\Scripts\main.lua` (`CONFIG` block):
`hide_seconds`, `hide_min_distance_m`, `hide_crouch_mult`.

## Compatibility
- PC (Steam) build with UE4SS + PalSchema. **Does not work** on the Xbox /
  Microsoft Store (Game Pass) version or consoles.
- Don't run it alongside "all Pals hostile" pak mods — they fight over the same
  data and defeat the curation/stealth.
- Plays nice with other UE4SS Lua and PalSchema mods.

## Credits
Created by Xidorian. Aggression/detection via **PalSchema** (Oak).
