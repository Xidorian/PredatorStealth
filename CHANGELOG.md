# Changelog — Predators & Stealth

## Unreleased (in testing)
Live-testing two fixes: aggressive Pals fleeing instead of fighting, and
traversal stutter on high-refresh setups. Not yet packaged or published.

**Performance**
- **Event-driven roster replaces the per-tick world sweep.** The scan used to call
  `FindAllOf("PalCharacter")` and re-resolve every Pal's class by reflection on
  every tick — a whole-array walk that blocked the game thread and grew heavier as
  Pals streamed in while moving, surfacing as repeated freezes on a 3440×1440@120
  setup. Pals are now added once (at load, then via `NotifyOnNewObject` as they
  spawn), their class + prey flag cached, and the scan walks that cached roster
  instead. A cheap full reconcile every `reseed_every_scans` ticks (default 8)
  catches anything the spawn notification missed. No behavior change — range,
  line-of-sight, crouch cone and hide-to-escape all work exactly as before. Scan
  duration is logged when `verbose` is on.

**Changed**
- **Acquisition range `base_range_m` 12 → 30.** Aggressive ("flee-then-fight")
  Pals were noticing the player and running at vanilla's perception range, which
  reaches farther than the old 12 m. In that gap they'd flee before the mod could
  force them into battle. The range now meets/exceeds vanilla's notice range so
  they get pulled into a fight instead. Still line-of-sight gated — a Pal only
  aggros when it can actually see you (the same moment vanilla would make it flee)
  — and crouch still scales the range down for stealth.
- **`max_aggros_per_scan` 4 → 8.** With the wider range more Pals can gain line of
  sight in a single scan tick; the old cap let the overflow get a free ~1.5 s to
  start fleeing before the next scan. Raised so everything with LOS in a tick is
  grabbed at once.

## 1.0.0
Initial release.

- Aggressive-by-default: every wild Pal hunts the player on sight except a curated
  passive **PreyList** (player-editable `PreyList.txt`).
- Line-of-sight-gated detection; range scales with level gap (capped).
- Crouch shrinks detection range and opens a rear stealth blind spot.
- Hide-to-escape: a pursuer that loses line of sight and gains distance for a few
  seconds gives up (clears its hate map + target list).
