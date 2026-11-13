# Attic

A native macOS front end for a retro game library: ROM folders laid out like
Batocera/ES-DE, scraping, RetroArch and standalone emulators, Cabinet Mode.
Never download or ship BIOS files: Attic only checks the ones people provide.

## Layout

- `project.yml` is the XcodeGen spec; the `.xcodeproj` is generated and gitignored. Edit `project.yml`, never the project. The version is `MARKETING_VERSION` there.
- `Attic/` the app. `Features/` has one folder per area (Library, Cabinet, Settings, Log, Onboarding, Tools, Commands, Help).
- `AtticKit/` Swift package, no UI: `AtticModels`, `AtticPersistence`, `AtticLibraryScanning`, `AtticScraping`, `AtticEmulation`, each with its tests in `AtticKit/Tests/`.
- `scripts/` build, signing, icon drawing, string sync and data import helpers.

## Build and check

- Build: `scripts/build.sh` → `dist/Attic.app` (regenerates the project first). `--open` launches it.
- Tests: `swift test --package-path AtticKit --scratch-path ~/Library/Developer/Attic/test-build`.
- After changing user-visible text: `scripts/sync-strings.sh`, then commit the updated catalogs.
- Release: `tools/release.sh <version>` (settings in `release.conf`). Use the mac-release skill.

## Git

- Commit after each working change, with a message that says what the user can now do.
