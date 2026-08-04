# NEXT — Predators & Stealth

**v2.1.0 is shipped.** The **C+D+E** batch is now **written and committed to `main`** (in live
testing — see `STATUS.md`). The one remaining task is **A**, held until the batch validates in play.

## Done in this batch (committed, awaiting live test)
- **C ✅** — 59 neutral field-boss rows flipped to `Warlike_Anyway` in `palschema/aggressive.jsonc` +
  `Scripts/aggressive_template.jsonc`, with matching `Scripts/pal_sizes.lua` entries (verified 1:1, no
  row dropped by the size filter; hostile-row count 324 → 383).
- **D ✅** — `main.lua` boss-freeze now keys off the pursuer's `CharacterID` row name (prefix `GYM_`/
  `RAID_`) via `pawn → CharacterParameterComponent → GetIndividualParameter() → GetCharacterID()`,
  not class-name substrings. Field alphas (`BOSS_*`) stay hideable.
- **E ✅** — new shared `Scripts/aggro_config.lua` resolver (ini + presets); PMO manifest expanded to
  difficulty preset + custom sliders + hide toggle; `main.lua` reads runtime knobs at boot,
  `aggro_options.lua` applies `detect_scale` to the regenerated patch.

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

## The remaining task

### A — de-aggro drops only YOU, not the pal's whole fight (CODE, do after the batch validates)
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
