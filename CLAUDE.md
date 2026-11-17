# Attic

A native macOS front end for a retro game library: ROM folders laid out like
Batocera/ES-DE, scraping, RetroArch and standalone emulators, Cabinet Mode.
Never download or ship BIOS files: Attic only checks the ones people provide.

Shared rules for how every project is laid out and named:
@~/.claude/project-layout.md

## Layout

- `project.yml` is the XcodeGen spec; the `.xcodeproj` is generated and gitignored. Edit `project.yml`, never the project. The version is `MARKETING_VERSION` there.
- `Attic/` the app. `Features/` has one folder per area (Library, Cabinet, Settings, Log, Onboarding, Tools, Commands, Help).
- `AtticKit/` Swift package, no UI: `AtticModels`, `AtticPersistence`, `AtticLibraryScanning`, `AtticScraping`, `AtticEmulation`, each with its tests in `AtticKit/Tests/`.
- `tools/` release, signing, icon drawing, string sync and data import helpers.

## Build and check

- Build: `./build.sh` → `dist/Attic.app` (regenerates the project first). `--open` launches it.
- Tests: `swift test --package-path AtticKit --scratch-path ~/Library/Developer/Attic/test-build`.
- Cabinet Mode pictures: `tools/snap.sh` (after `./build.sh`) writes `/tmp/Attic-shots/<theme>-<art>.png` for every built-in theme from a made-up library in /tmp; `ATTIC_SNAPSHOT_THEMES` and `ATTIC_SNAPSHOT_ARTS` narrow it. It never opens the real library. Look at them after any Cabinet change.
- After changing user-visible text: `tools/sync-strings.sh`, then commit the updated catalogs.
- Release: `tools/release.sh <version>` (settings in `release.conf`). Use the mac-release skill.

## Git

- Commit after each working change, with a message that says what the user can now do.
