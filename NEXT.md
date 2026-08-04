# NEXT — Predators & Stealth

**v2.1.0 is shipped + uploaded.** Below is a fully-scoped batch (C → D → E, commit, then A),
ready for a fresh session. All findings are captured so nothing needs re-deriving.

## Key reference (verified 2026-08-04)
- **`C:/Users/Xidorian/Documents/Projects/PalworldMods/PalClassification.csv`** — the authoritative
  `DT_PalMonsterParameter` dump, 754 rows. Columns: `Pal,Predator,Edible,Nocturnal,AIResponse,
  AISightResponse,ViewingDistance,ViewingAngle,HearingRate,Size,GenusCategory,Rarity,Hp,IsBoss,
  IsTowerBoss,IsRaidBoss`. Size col = EPalSizeType int (1=XS 2=S 3=M 4=L 5=XL).
- **Boss row families:** `GYM_*` (21, tower bosses, IsTowerBoss) · `RAID_*` (19, raid bosses,
  IsRaidBoss) · `BOSS_*` (319 field/dungeon variants; **260 are `AIResponse=Boss` already-aggressive,
  59 are `NotInterested`/`Escape` = the NEUTRAL field alphas**, incl. `BOSS_GrassMammoth` = Mammorest).
- **Callable UFunctions** on `UPalDatabaseCharacterParameter` (`FindFirstOf("PalDatabaseCharacterParameter")`):
  `GetSize(FName)->EPalSizeType`, `GetIsBoss(FName)->bool`, `GetIsTowerBoss(FName)->bool`. Char has an
  `IsPredator` bool field. `UPalHate` has `ChangeHate()`. Controller has `TargetPlayers` (players) AND
  `TargetNPCs` (pals/otomo) — see [[palschema-pivot]], [[palworld-sdk-dump]].

## The batch — do in order, commit C+D+E together, then A separately

### C — make the 59 neutral field bosses hunt you (DATA)
- Rule: every `BOSS_*` row whose `AIResponse` is `NotInterested`/`Escape*` → `Warlike_Anyway`.
  Get the list: `awk -F, 'NR>1 && $1 ~ /^BOSS_/ && ($5=="NotInterested"||$5 ~ /Escape/){print $1}' PalClassification.csv` (59 rows).
- Add those rows to BOTH `palschema/aggressive.jsonc` AND `Scripts/aggressive_template.jsonc` (keep
  identical). Do NOT touch `GYM_*`/`RAID_*` or the 260 already-`Boss` rows.
- **CRITICAL:** also add each new `BOSS_*` row to `Scripts/pal_sizes.lua` with its Size (CSV col 10).
  The options menu FILTERS the template by size — a row missing from `pal_sizes.lua` gets dropped.
- Sight/hearing for the new rows: match the base species' values from our patch if present, else default
  `ViewingDistance:25, HearingRate:10.0`.

### D — boss-freeze via the game's flags, not name guesses (CODE, main.lua)
- Only `GYM_*` (tower) + `RAID_*` (raid) should get the de-aggro freeze (can't hide from a scripted
  boss; its scripted defeat is a crash risk). Field alphas (`BOSS_*`) must stay hideable.
- Replace `CONFIG.boss_markers` substring-matching. Robust path: read the pawn's **CharacterID (row
  name)** — `APalCharacter` → individual parameter → `CharacterID` (verify the accessor in the SDK
  dump) — and freeze if it starts with `GYM_`/`RAID_`, or call `db:GetIsTowerBoss(rowName)`. Current
  `"Gym"` marker catches Grizzbolt but raid/tower are unverified (class-name vs row-name is unconfirmed).

### E — tunables menu: presets + individual options (FEATURE, aggro_options.lua + main.lua)
- Add to the PMO manifest: a **difficulty preset** enum (Relaxed/Normal/Hardcore/**Custom**) + individual
  options: give-up time (`hide_seconds`), give-up distance (`hide_min_distance_m`), crouch bonus
  (`hide_crouch_mult`), detection-range scale (× on ViewingDistance/HearingRate), hide-to-escape on/off.
- Preset interaction: if preset ≠ Custom, it drives the values; Custom uses the individual sliders.
- Runtime knobs (give-up time/distance/crouch/hide-toggle) are read by **main.lua** from the PMO `.ini`
  at load (add a reader like aggro_options'; `game_restart` mode = no race). The detection-range scale is
  a DATA knob — `aggro_options.lua` scales ViewingDistance/HearingRate when it regenerates the effective
  `aggressive.jsonc`.

### A — de-aggro drops only YOU, not the pal's whole fight (CODE, do LAST)
- This is the **your-pal-vs-mobs** resolution (a real fix, not wontfix): a wild pal shouldn't stop
  attacking your otomo just because it lost sight of *you*. Player then chooses to let the pal tank
  (it may die) or bail.
- In `clearAggro`: keep `TargetPlayers:Empty()` (players only), but replace `HateMap:Empty()` with
  removing ONLY the player's hate — `UPalHate:ChangeHate(playerInstanceId, -big)` (need the player's
  `FPalInstanceID` from the player character's individual parameter). The wild pal keeps its `TargetNPCs`
  (otomo) and keeps fighting it.
- Biggest teardown/hate-map subtlety — do it last, test carefully (crash-safety still applies).

## Later / idea backlog
- More menu tunables beyond E; level-gap sight scaling (per-instance `SightDistance` IS settable);
  boss-marker/multiplayer verification through play.

## Watch
- Crash stability — if one recurs, recover the crash-trace from tag `archive/crash-instrumented-2026-08-04`.
