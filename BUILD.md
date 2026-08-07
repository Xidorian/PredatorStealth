# Predators & Stealth — build & release how-to

Self-contained checklist for cutting a release. Written so a future build needs **zero
re-discovery** — don't re-read the zips or reverse-engineer the layout; it's all here.
(A copy also lives in the `PalworldMods` hub as a worked example.)

## ⚠ THE WORKSHOP-VS-ZIP STRUCTURE TRAP (this broke v2.1.0 on Steam — read first)

The **zip** artifacts and the **Steam Workshop** artifact have DIFFERENT folder trees. Uploading the
zip/staging tree to Workshop is exactly the bug that shipped in v2.1.0 (mod did nothing for everyone):

- **Zips** are extracted straight into `…/UE4SS/Mods/`, so they carry the FULL install paths:
  `PalSchema/mods/PredatorStealth/raw/aggressive.jsonc` and `PredatorStealth/Scripts/*.lua`.
- **Workshop** applies `Info.json`'s `InstallRule`, which PREPENDS the base path itself:
  `Type: Lua` → `Mods\{PackageName}\` · `Type: PalSchema` → `Mods\PalSchema\mods\{PackageName}\`.
  So the uploaded `workshop-upload/` folder must be **FLAT relative to those bases**:
  - `workshop-upload/Scripts/*.lua`  (NOT `workshop-upload/PredatorStealth/Scripts/…`)
  - `workshop-upload/PalSchema/raw/aggressive.jsonc`  (NOT `…/PalSchema/mods/PredatorStealth/raw/…`)

  Verified against working Workshop mods on 2026-08-07: SmartPause (`Type: Lua, Targets:["./Scripts"]`,
  ships `Scripts/main.lua` at root) and SuperStacksNoLag (`Type: PalSchema, Targets:["./PalSchema/"]`,
  ships `PalSchema/blueprints/…jsonc` FLAT). v2.1.0 wrongly uploaded the zip tree → `./Scripts` didn't
  exist (Lua mod never installed → no menu, no hide-to-escape) AND `./PalSchema/` was double-nested to
  `PalSchema/mods/PredatorsandStealth/mods/PredatorStealth/raw/` (data patch never loaded → no aggro).

**Rule: for Steam Workshop, upload the `workshop-upload/` folder as-is. Never point the uploader at a
zip, the zip staging dir, or an extracted zip.**

## What actually ships (3 artifacts, from the same source)

The mod is **two parts**: a UE4SS Lua mod (Scripts) + a PalSchema data patch (`aggressive.jsonc`).
Every artifact carries both.

The **Scripts files** (main.lua's guarded `require`s expect ALL of these — a missing one silently
breaks the menu/tunables, which is how `aggro_config.lua` got left out of an earlier build):
- `main.lua` — hide-to-escape runtime + reads the PMO tunables.
- `aggro_config.lua` — shared resolver: reads the PMO `.ini`, holds the difficulty presets. **Required
  by both `main.lua` and `aggro_options.lua`** — omit it and the menu/tunables fail.
- `aggro_options.lua` — the PalModOptions page + regenerates the effective patch from the toggles.
- `pal_sizes.lua` — baked species→size map.
- `mount_aggro.lua` — mounted-aggro helper (`require`d by `main.lua`).
- `aggressive_template.jsonc` — the stable full patch the applier filters. **Must be byte-identical
  to `PalSchema\…\raw\aggressive.jsonc`** (which is the no-PalModOptions default); both come from
  `palschema/aggressive.jsonc`, so ship that same file to both spots.
- (DEV-only, NEVER ship: `grade_probe.lua`, `dump_presets.lua`, `predator_presets.lua`.)

| Artifact | For | Contains | Notes |
|---|---|---|---|
| `PredatorStealth-<ver>.zip` | **NexusMods** / manual RE-UE4SS | `PalSchema\…\aggressive.jsonc`, `PredatorStealth\Scripts\{main,aggro_config,aggro_options,pal_sizes,mount_aggro}.lua` + `aggressive_template.jsonc`, `PredatorStealth\enabled.txt`, `INSTALL.txt` | **has `enabled.txt`** (auto-enables on standard RE-UE4SS) |
| `PredatorStealth-Steam-<ver>.zip` | **Steam** manual install | same, **minus `enabled.txt`** | Steam-Workshop UE4SS enables via `Mods\mods.txt` instead |
| `workshop-upload/` (folder) | **Steam Workshop uploader** | `Info.json`, `Scripts/{main,aggro_config,aggro_options,pal_sizes,mount_aggro}.lua` + `Scripts/aggressive_template.jsonc`, `PalSchema/raw/aggressive.jsonc`, `thumbnail.jpg/.png` | Info.json-driven (`InstallRule`); **flat** `PalSchema/raw/` + `Scripts/` at root (see the Workshop-vs-zip trap above) |

**PalModOptions** is an **optional** runtime dependency (feature-detected). Without it the mod runs
as before — every Pal size hostile. Note it in `Info.json`/`INSTALL.txt`/`MODPAGE.md`, don't bundle it.

The only difference between the two zips is the presence of `enabled.txt`. The
`workshop-upload/` folder has a **different tree** — driven by `Info.json`'s `InstallRule`.

## Source of truth (edit these; everything else is generated)

- `Scripts/main.lua` — the runtime. **Ship with `verbose = false`** + no dev instrumentation (step 1).
- `Scripts/aggro_config.lua` — shared PMO `.ini` reader + difficulty presets. **Required by main.lua and
  aggro_options.lua**; ship as-is. (This is the file an earlier build forgot — don't.)
- `Scripts/mount_aggro.lua` — mounted-aggro helper (`require`d by main.lua). Ship as-is.
- `Scripts/aggro_options.lua` — PalModOptions page + effective-patch regeneration. Ship as-is.
- `Scripts/pal_sizes.lua` — baked species→size map. Regenerate with the size probe only if a game
  update adds/renames pals (see `AGGRO-OPTIONS.md`); raw extract is `palschema/pal-sizes.tsv`.
- `Scripts/aggressive_template.jsonc` — the applier's stable source. Keep **identical** to
  `palschema/aggressive.jsonc` (it's a copy: `cp palschema/aggressive.jsonc Scripts/aggressive_template.jsonc`).
- `palschema/aggressive.jsonc` — the data patch (also the no-PalModOptions default). Rule: currently
  ALL species `Warlike_Anyway` (was: vanilla `Escape_to_Battle` → `Warlike_Anyway`, else `Warlike`;
  blanketed in 2.1.0 to also aggro mounted/gliding players). Baseline `AIResponse` per species is
  column 5 of `PalworldMods/PalClassification.csv`.
- `Info.json` — package manifest (version, deps, `InstallRule`).
- `CHANGELOG.md`, `MODPAGE.md` — docs.
- `enabled.txt` — empty marker file (Nexus zip only).
- `*.zip` are **gitignored**; `workshop-upload/` is **untracked** (both are build output).
  Thumbnails currently live only in `workshop-upload/` — don't delete that folder.

## Release steps

1. **Strip dev instrumentation from `Scripts/main.lua` (STANDARD every release):** `verbose = false`,
   and remove any DEV-only diagnostics (e.g. the flush-safe crash-trace facility + its breadcrumbs,
   the stutter meter). `grep -nE "trace\(|TRACE|STUTTER|ExecuteInGameThread" Scripts/main.lua` should
   come back empty (bar the "removed" comments). These live on a branch/tag for testing, never in a release.
2. **Bump the version** in three places (keep them in sync): `Info.json`,
   `workshop-upload/Info.json`, and the `## <ver>` heading in `CHANGELOG.md`
   (rename `## Unreleased (in testing)` → `## <ver>`). Also bump `MODPAGE.md` `## Version`.
   Versioning: bug-fix over a tagged release → patch bump (e.g. `2.0.0`→`2.0.1`).
3. **Refresh `workshop-upload/`** with the final source:
   ```bash
   cp Scripts/main.lua                  workshop-upload/Scripts/main.lua
   cp Scripts/aggro_config.lua          workshop-upload/Scripts/aggro_config.lua
   cp Scripts/aggro_options.lua         workshop-upload/Scripts/aggro_options.lua
   cp Scripts/pal_sizes.lua             workshop-upload/Scripts/pal_sizes.lua
   cp Scripts/mount_aggro.lua           workshop-upload/Scripts/mount_aggro.lua
   cp Scripts/aggressive_template.jsonc workshop-upload/Scripts/aggressive_template.jsonc
   cp palschema/aggressive.jsonc        workshop-upload/PalSchema/raw/aggressive.jsonc
   # then bump "Version" in workshop-upload/Info.json to match (and confirm InstallRule covers Scripts/*)
   ```
4. **Build the two zips** (see below).
5. **Verify** (see below).
6. **Commit** the source changes (not the zips — they're gitignored), **push**, **tag**:
   ```bash
   git add Scripts/main.lua palschema/aggressive.jsonc Info.json CHANGELOG.md MODPAGE.md
   git commit    # release notes in the body
   git tag -a v<ver> -m "Predators & Stealth v<ver>"
   git push origin main && git push origin v<ver>
   ```
   (Releases go straight to `main` — that's the established pattern; `v2.0.0`/`v2.0.1`
   tags are on `main`.)
7. Upload (by hand in each tool — the build only produces the files):
   - **NexusMods** ← `PredatorStealth-<ver>.zip`
   - **Steam manual-install** ← `PredatorStealth-Steam-<ver>.zip`
   - **Steam WORKSHOP** ← point the PalworldModUploader at the **`workshop-upload/` folder** (NOT a
     zip, NOT the `$STAGE` staging dir, NOT an extracted zip). This is the v2.1.0 trap — see the top.

## Build commands

`zip` is **not** available in Git Bash here — use PowerShell `Compress-Archive`.
Stage the shared tree in Bash, then zip twice (Nexus = with `enabled.txt`, Steam = without).

**Bash — stage the tree + INSTALL.txt:**
```bash
STAGE="$(mktemp -d)/pkg"; mkdir -p "$STAGE/PalSchema/mods/PredatorStealth/raw" "$STAGE/PredatorStealth/Scripts"
cp palschema/aggressive.jsonc "$STAGE/PalSchema/mods/PredatorStealth/raw/aggressive.jsonc"
cp Scripts/main.lua                  "$STAGE/PredatorStealth/Scripts/main.lua"
cp Scripts/aggro_config.lua          "$STAGE/PredatorStealth/Scripts/aggro_config.lua"
cp Scripts/aggro_options.lua         "$STAGE/PredatorStealth/Scripts/aggro_options.lua"
cp Scripts/pal_sizes.lua             "$STAGE/PredatorStealth/Scripts/pal_sizes.lua"
cp Scripts/mount_aggro.lua           "$STAGE/PredatorStealth/Scripts/mount_aggro.lua"
cp Scripts/aggressive_template.jsonc "$STAGE/PredatorStealth/Scripts/aggressive_template.jsonc"
# write INSTALL.txt (bump the version line + note PalModOptions is optional); see the current one for wording
```

**PowerShell — build both zips** (`$stage` = the staging dir, `$repo` = repo root):
```powershell
$ps = "$stage\PredatorStealth"
# Nexus: WITH enabled.txt
if (-not (Test-Path "$ps\enabled.txt")) { New-Item -ItemType File "$ps\enabled.txt" | Out-Null }
Compress-Archive -Path "$stage\PalSchema","$stage\PredatorStealth","$stage\INSTALL.txt" `
  -DestinationPath "$repo\PredatorStealth-<ver>.zip" -Force
# Steam: WITHOUT enabled.txt
Remove-Item "$ps\enabled.txt" -Force
Compress-Archive -Path "$stage\PalSchema","$stage\PredatorStealth","$stage\INSTALL.txt" `
  -DestinationPath "$repo\PredatorStealth-Steam-<ver>.zip" -Force
```
`Compress-Archive` writes **backslash** path separators in the archive — that's normal on
Windows PowerShell 5.1 and matches every prior release; Windows extractors and the mod
loader handle it fine. `unzip -p` with forward slashes won't match those entries — extract
to a temp dir to inspect instead.

## Verify before uploading

```bash
unzip -l PredatorStealth-<ver>.zip        # Nexus: PalSchema patch + 4 Scripts files + enabled.txt + INSTALL.txt
unzip -l PredatorStealth-Steam-<ver>.zip  # Steam: same, NO enabled.txt
# content spot-check (extract, since paths use backslashes):
cd "$(mktemp -d)" && unzip -q "<repo>/PredatorStealth-<ver>.zip"
grep -n 'verbose  *=' PredatorStealth/Scripts/main.lua                 # must be false
grep -cE 'trace\(|TRACE|STUTTER' PredatorStealth/Scripts/main.lua      # must be 0 (dev stripped)
ls PredatorStealth/Scripts/                                            # main + aggro_config + aggro_options + pal_sizes + mount_aggro + aggressive_template (6 files; NO grade_probe/dump_presets/predator_presets)
diff PredatorStealth/Scripts/aggressive_template.jsonc \
     PalSchema/mods/PredatorStealth/raw/aggressive.jsonc               # must be identical (template == default)
grep -oE '"AIResponse": "[A-Za-z_]+"' PalSchema/mods/PredatorStealth/raw/aggressive.jsonc | sort | uniq -c   # AIResponse mix as intended
head -1 INSTALL.txt                                                    # version matches
```

**Steam Workshop structure check (the v2.1.0 trap — do NOT skip):**
```bash
find workshop-upload -type f | sort
# MUST show, and NOTHING more nested:
#   workshop-upload/PalSchema/raw/aggressive.jsonc          (NOT .../PalSchema/mods/…/raw/…)
#   workshop-upload/Scripts/{main,aggro_config,aggro_options,pal_sizes,mount_aggro}.lua + aggressive_template.jsonc
#   workshop-upload/Info.json + thumbnails
test ! -d workshop-upload/PalSchema/mods && echo "PalSchema OK (flat)" || echo "BUG: nested PalSchema/mods!"
test -f workshop-upload/Scripts/aggro_config.lua && echo "aggro_config present" || echo "BUG: aggro_config missing!"
grep -n 'verbose  *=' workshop-upload/Scripts/main.lua                 # must be false before upload
```
Also confirm `Info.json`, `workshop-upload/Info.json`, `CHANGELOG.md`, and `INSTALL.txt`
all show the new version.
