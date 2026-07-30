# Predators & Stealth — build & release how-to

Self-contained checklist for cutting a release. Written so a future build needs **zero
re-discovery** — don't re-read the zips or reverse-engineer the layout; it's all here.
(A copy also lives in the `PalworldMods` hub as a worked example.)

## What actually ships (3 artifacts, from the same source)

The mod is **two parts**: a UE4SS Lua script (`PredatorStealth/`) + a PalSchema data
patch (`PalSchema/mods/PredatorStealth/raw/`). Every artifact carries both.

| Artifact | For | Contains | Notes |
|---|---|---|---|
| `PredatorStealth-<ver>.zip` | **NexusMods** / manual RE-UE4SS | `PalSchema\…\aggressive.jsonc`, `PredatorStealth\Scripts\main.lua`, `PredatorStealth\enabled.txt`, `INSTALL.txt` | **has `enabled.txt`** (auto-enables on standard RE-UE4SS) |
| `PredatorStealth-Steam-<ver>.zip` | **Steam** manual install | same, **minus `enabled.txt`** | Steam-Workshop UE4SS enables via `Mods\mods.txt` instead |
| `workshop-upload/` (folder) | **Steam Workshop uploader** | `Info.json`, `Scripts/main.lua`, `PalSchema/raw/aggressive.jsonc`, `thumbnail.jpg/.png` | Info.json-driven (`InstallRule`); **flat** `PalSchema/raw/`, not `PalSchema/mods/PredatorStealth/raw/` |

The only difference between the two zips is the presence of `enabled.txt`. The
`workshop-upload/` folder has a **different tree** — driven by `Info.json`'s `InstallRule`.

## Source of truth (edit these; everything else is generated)

- `Scripts/main.lua` — the runtime. **Ship with `verbose = false`** (top `CONFIG` block).
- `palschema/aggressive.jsonc` — the data patch. Rule: vanilla `Escape_to_Battle`
  species → `Warlike_Anyway`; everything else → `Warlike`. (Baseline `AIResponse` per
  species is column 5 of `PalworldMods/PalClassification.csv`.)
- `Info.json` — package manifest (version, deps, `InstallRule`).
- `CHANGELOG.md`, `MODPAGE.md` — docs.
- `enabled.txt` — empty marker file (Nexus zip only).
- `*.zip` are **gitignored**; `workshop-upload/` is **untracked** (both are build output).
  Thumbnails currently live only in `workshop-upload/` — don't delete that folder.

## Release steps

1. **Confirm the runtime is ship-ready:** `verbose = false` in `Scripts/main.lua`.
2. **Bump the version** in three places (keep them in sync): `Info.json`,
   `workshop-upload/Info.json`, and the `## <ver>` heading in `CHANGELOG.md`
   (rename `## Unreleased (in testing)` → `## <ver>`). Also bump `MODPAGE.md` `## Version`.
   Versioning: bug-fix over a tagged release → patch bump (e.g. `2.0.0`→`2.0.1`).
3. **Refresh `workshop-upload/`** with the final source:
   ```bash
   cp Scripts/main.lua           workshop-upload/Scripts/main.lua
   cp palschema/aggressive.jsonc workshop-upload/PalSchema/raw/aggressive.jsonc
   # then bump "Version" in workshop-upload/Info.json to match
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
7. Upload: the Nexus zip → NexusMods; the Steam zip and/or `workshop-upload/` → Steam.
   (Uploading is done by hand in each site's tool — the build only produces the files.)

## Build commands

`zip` is **not** available in Git Bash here — use PowerShell `Compress-Archive`.
Stage the shared tree in Bash, then zip twice (Nexus = with `enabled.txt`, Steam = without).

**Bash — stage the tree + INSTALL.txt:**
```bash
STAGE="$(mktemp -d)/pkg"; mkdir -p "$STAGE/PalSchema/mods/PredatorStealth/raw" "$STAGE/PredatorStealth/Scripts"
cp palschema/aggressive.jsonc "$STAGE/PalSchema/mods/PredatorStealth/raw/aggressive.jsonc"
cp Scripts/main.lua           "$STAGE/PredatorStealth/Scripts/main.lua"
# write INSTALL.txt (bump the version line); see the current one for exact wording
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
unzip -l PredatorStealth-<ver>.zip        # expect 6 files incl. PredatorStealth\enabled.txt
unzip -l PredatorStealth-Steam-<ver>.zip  # expect 5 files, NO enabled.txt
# content spot-check (extract, since paths use backslashes):
cd "$(mktemp -d)" && unzip -q "<repo>/PredatorStealth-<ver>.zip"
grep -n 'verbose  *=' PredatorStealth/Scripts/main.lua                 # must be false
grep -c '"AIResponse": "Warlike_Anyway"' PalSchema/mods/PredatorStealth/raw/aggressive.jsonc
head -1 INSTALL.txt                                                    # version matches
```
Also confirm `Info.json`, `workshop-upload/Info.json`, `CHANGELOG.md`, and `INSTALL.txt`
all show the new version.
