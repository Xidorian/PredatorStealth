# Changelog — Predators & Stealth

## Unreleased (in testing)
Live-testing a fix for aggressive Pals fleeing instead of fighting. Not yet
packaged or published.

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
