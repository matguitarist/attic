# Attic

A native macOS front end for your retro game library.

Point Attic at a ROMs folder organized the way Batocera, RetroBat or ES-DE do
it (one subfolder per system) and it builds a browsable library with box
art, screenshots and descriptions, then launches games in RetroArch or a
standalone emulator.

- **Library**: grid of covers, favorites, recently played, collections,
  search, and a detail panel where any info can be edited by hand.
- **Scraping**: descriptions, dates, genres and artwork from ScreenScraper
  or TheGamesDB, for one game, a selection, a collection or a whole system.
  Existing ES-DE gamelists and downloaded media are picked up as they are.
- **Emulators**: installs RetroArch, its cores and standalone emulators from
  their official sources, and keeps everything (BIOS, saves, states,
  settings) in one Emulation folder you can back up or move.
- **System Settings**: per system, how games look (sharp pixels, CRT,
  handheld LCD or any RetroArch shader) and play (internal resolution,
  widescreen, run-ahead, rewind, resume where you left off).
- **Cabinet Mode**: a full-screen, controller-driven view for the TV.
- **Controllers**: one button mapping applied across emulators.

Attic never downloads BIOS files; it only checks the ones you provide.

## Requirements

macOS 26 or later.

## Install

**[Download Attic for Mac](https://github.com/matguitarist/attic/releases/latest/download/Attic.dmg)**

Open the disk image and drag **Attic** onto **Applications**. Attic is
signed and notarized by Apple, and updates itself (Attic › Check for
Updates…).

## Building

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/build.sh --open      # Release build into dist/, then launch it
cd AtticKit && swift test    # the package's tests
```

The Xcode project is generated from `project.yml` and isn't committed. For
signed builds, put your team in `Config/Signing.local.xcconfig` (see
`Config/Signing.xcconfig`).

`scripts/release.sh` publishes the version in `project.yml` as a GitHub
release and adds it to the Sparkle appcast; its header lists what it needs.

## License

Attic is free and open source (MIT license). It isn't affiliated with
RetroArch, libretro, ScreenScraper or TheGamesDB.

System logos are by Dan Patrick
([Console Logos Professionally Redrawn](https://archive.org/details/console-logos-professionally-redrawn-plus-official-versions)),
not covered by the MIT license and never to be sold; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
