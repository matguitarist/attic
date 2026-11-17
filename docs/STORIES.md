# Attic user stories

Attic is a native macOS front end for a retro game library: ROM folders laid
out like Batocera/ES-DE, scraping, RetroArch and standalone emulators, and
Cabinet Mode for the couch or a real cabinet.

This file was written on 2026-11-13, at version 2.10.2, from the app as it
ships and from the Attic Roadmap project in Thimble. Stories marked `done`
describe what Attic already does, so they can be checked again after changes.
Stories marked `todo` are the open roadmap items.

Attic has no snapshot mode yet, so `Screens:` names the view that shows each
story (the Swift file under `Attic/Features/`).

---

## M1 Library: open a ROMs folder and see the games

### S-001 Choose the ROMs folder on first launch
As the user, I pick my ROMs folder (Batocera, RetroBat or ES-DE layout) the first time I open Attic.
Screens: Onboarding/ChooseROMsRootView
Acceptance:
- [manual] A folder laid out like Batocera (`roms/<system>`) or ES-DE (`~/ES-DE`, flat or shared parent) is accepted and scanned.
- [unit] `LibraryScanner` finds every system folder it knows and ignores folders it doesn't.
- [unit] The library and settings survive a restart (SwiftData store).
Status: done

### S-002 Browse systems in the sidebar
As the user, I see my systems grouped by kind, with their logos, and sort them from one menu.
Screens: Library/LibrarySidebarView
Depends: S-001
Acceptance:
- [manual] Systems sit under kind headers (consoles, handhelds, arcade, computers…) with short names and logos.
- [manual] One sort menu next to the sidebar button sorts every kind.
- [manual] Systems with no games can be hidden.
Status: done

### S-003 Browse a system's games as a cover grid
As the user, I select a system and see its games as covers, with clean names instead of file names.
Screens: Library/GameGridView, Library/GameCoverCell
Depends: S-002
Acceptance:
- [unit] `ROMFilenameTitleCleaner` turns "Sonic (USA, Europe) (Rev 1).md" into "Sonic".
- [manual] A zoom slider changes cover size; columns fit small screens.
- [manual] Search and sort pills filter the grid.
Status: done

### S-004 Read a game's details in the inspector
As the user, I select a game and see its cover, description, info, media and video in the side panel.
Screens: Library/GameDetailView, Library/GameMediaSection, Library/VideoPreviewView
Depends: S-003
Acceptance:
- [manual] Cover, logo, screenshots, fan art, manual and video preview show when they exist.
- [manual] With no game selected, the panel shows the system overview (S-005).
Status: done

### S-005 Read a system's overview
As the user, I see a system's ROM folder, file types, BIOS files, recommended emulator and Wikipedia link.
Screens: Library/SystemOverviewView, Library/SystemSections
Depends: S-002
Acceptance:
- [manual] File types and BIOS file names show as tags.
- [manual] Scrape This System, Refresh This System and Verify Games are buttons on the panel.
Status: done

### S-006 Take in an existing front-end's gamelists and play history
As the user, my ES-DE or Batocera gamelists, media and play counts show up without scraping again.
Screens: Library/GameDetailView
Depends: S-001
Acceptance:
- [unit] `BatoceraGamelistParser` and `ESDEGamelistMapper` read names, descriptions, ratings, players, play count and last played.
- [unit] A gamelist.xml that fails to parse falls back to listing the ROMs.
Status: done

### S-007 Edit a game's info
As the user, I change a game's name, genre, year or description in the panel, and a rescan keeps my edit.
Screens: Library/EditGameInfoView
Depends: S-004
Acceptance:
- [unit] Edited and scraped fields aren't overwritten by a rescan.
Status: done

---

## M2 Play: start a game in the right emulator

### S-010 Play a game with RetroArch
As the user, I double-click a game (or press Play) and it starts in the RetroArch core chosen for its system.
Screens: Library/GameGridView, Settings/RetroArchSettingsView
Depends: S-003
Acceptance:
- [unit] `RetroArchLauncher` builds the command line for the system's core.
- [unit] Zipped ROMs a core can't open are extracted first (`ZippedROMExtractor`).
- [manual] A play session is recorded: play time and last played update when the game quits.
Status: done

### S-011 Play with a standalone or custom emulator
As the user, I set PCSX2, DuckStation, Vita3K, shadPS4 or my own emulator for a system, or pick one with Launch With.
Screens: Library/EmulatorPicker, Settings/EmulatorProfileEditorView, Settings/CustomEmulatorsSection
Acceptance:
- [unit] `ArgumentTemplate` fills `{rom}` and the other placeholders.
- [manual] Launch With in the context menu lists every emulator that runs the system.
Status: done

### S-012 Install and update cores and emulators
As the user, I install a missing core or standalone emulator from Settings and update all of them in one click.
Screens: Settings/RetroArchSettingsView, Library/EmulatorSuggestionView
Acceptance:
- [manual] Update All updates cores and standalone emulators; every failed install is reported.
- [unit] `CoreUpdateChecker` finds cores newer than the installed ones.
Status: done

### S-013 See which BIOS files are missing
As the user, I see every system's BIOS files as Found or Missing, checked by checksum, in Settings › BIOS and on the system panel.
Screens: Settings/BIOSSettingsView, Library/MissingBIOSAlert
Acceptance:
- [unit] `BIOSChecksums` matches files by MD5, not only by name; an unknown dump can be compared.
- [unit] Checks follow the chosen core and refresh when Attic comes back to the front.
- [manual] A game that needs a missing BIOS doesn't start and says which file is missing.
- [manual] Attic never downloads BIOS files.
Status: done

### S-014 Locate a missing arcade BIOS set
As the user, I click Locate… or Search a Folder and Attic puts each BIOS set where its emulator looks.
Screens: Library/BIOSSetLocating, Library/GameInfoHealthView
Depends: S-013
Acceptance:
- [manual] Only the set's exact name can be picked.
- [unit] Sets for sm2-emu (Model 1 I/O) and Odin (Hikaru) are copied beside the games.
Status: done

### S-015 Learn why a game didn't start
As the user, a game that fails to start shows why, and the Log window shows what Attic did and what the emulator said.
Screens: Library/FailedLaunchAlert, Log/LogView
Acceptance:
- [manual] The Log is color-coded and opens from the toolbar.
Status: done

### S-016 Pick a shader per system
As the user, I choose a retro look (or None) for each system, from the shader library or my own files.
Screens: Settings/ShadersSection, Library/SystemSettingsView
Acceptance:
- [manual] Each setting names what Default means for that system.
Status: done

### S-017 Earn RetroAchievements
As the user, I sign in once and RetroArch, DuckStation and PCSX2 track achievements.
Screens: Settings/RetroAchievementsSection
Acceptance:
- [unit] Credentials are written to each emulator's config at launch.
Status: done

### S-018 Play with my controller
As the user, Attic recognizes my pad (Xbox, PlayStation, Switch 2 Pro over USB) and shows matching button icons.
Screens: Settings/ControllerSettingsView
Acceptance:
- [unit] `Switch2Pad` and `XInputPadState` decode the reports.
- [manual] Button hints in Cabinet Mode match the pad in use.
Status: done

### S-019 Back up saves
As the user, my save files are backed up so a bad session can be undone.
Screens: Settings/GeneralSettingsView
Acceptance:
- [unit] `SaveBackup` copies saves before launch and keeps a limited history.
Status: done

---

## M3 Scrape and media

### S-020 Scrape missing info and art
As the user, I select games (or a system) and choose Scrape Missing to fill in info, covers, screenshots, logos, fan art and videos.
Screens: Library/ScrapeMissingButton, Library/BatchScrapeStatusBar
Depends: S-003
Acceptance:
- [manual] ScreenScraper, TheGamesDB and LaunchBox can each be the source; credentials sit in one Keychain item.
- [unit] Arcade boards scrape from their own ScreenScraper systems.
- [manual] Progress shows in a status bar; replaced media shows at once.
Status: done

### S-021 Get artwork for Steam games
As the user, I import my Steam games and they get SteamGridDB artwork and Steam trailers.
Screens: Settings/SteamGridDBSettingsView
Acceptance:
- [unit] `SteamLibrary` lists installed games; `SteamGridDB` maps them to art.
Status: done

### S-022 Download videos from EmuMovies
As the user, I sign in to EmuMovies and fill in missing videos and media.
Screens: Settings/EmuMoviesSettingsView, Tools/EmuMoviesReportView
Status: done

### S-023 See which games are missing media
As the user, Media Health shows which games lack a cover, logo, video or other kind, and likely wrong metadata.
Screens: Library/MediaHealthView, Library/GameInfoHealthView
Acceptance:
- [unit] `MediaHealth` and `MetadataCheck` count what's missing per system.
Status: done

### S-024 Import media from another front-end
As the user, Tools › Import from Another Front-End takes media and info from RetroBat or Batocera, for the systems I choose, and copies games I don't have.
Screens: Tools/MediaImportReportView
Acceptance:
- [unit] `ESDEMediaResolver` and `FrontEndMedia` find each media kind; logos convert to HEIC.
Status: done

---

## M4 Organize

### S-030 Make a collection from a search
As the user, I build a collection from several search terms, leave some out with "But not", and pick games by hand.
Screens: Library/Collections, Settings/CollectionsSettingsView
Acceptance:
- [unit] `CollectionSearch` matches several terms and excludes the "But not" ones.
- [manual] A collection keeps its search and can keep up with new games by itself.
Status: done

### S-031 Make a collection from a series template
As the user, I start a collection from a series template and it takes its logo from a folder of series logos.
Screens: Library/CollectionOverviewView
Acceptance:
- [unit] `SeriesTemplates` lists the built-in series.
Status: done

### S-032 Filter a collection by genre, players, years or favorites
As the user, a collection can choose games by genre, players, years and favorites.
Screens: Library/Collections
Status: done

### S-033 Use ES-DE collections
As the user, my ES-DE custom collections show up in Attic.
Screens: Library/LibrarySidebarView
Acceptance:
- [unit] `ESDECustomCollection` reads and writes the cfg files.
Status: done

### S-034 Favorite a game
As the user, I mark a game as a favorite from its panel or context menu.
Screens: Library/GameMenuItems
Status: done

### S-035 Find something to play
As the user, I open Recently Added, pick a random game, or look at library statistics.
Screens: Library/LibraryStatsView
Status: done

---

## M5 Library care (Tools)

### S-040 Add games by dropping them
As the user, I drop ROMs, whole folders (with media and gamelist), PS Vita and PS4 games on Attic and they go to the right system folder.
Screens: Library/ROMImportSheet, Library/ROMImportStatusBar
Acceptance:
- [unit] `ROMImport` picks the system from the extension, or from the arcade name index.
- [manual] The import runs in the background with progress.
Status: done

### S-041 Tidy up the library
As the user, Tidy Up analyzes first, then I approve a report that moves media, cleans gamelists, finds duplicates and keeps a ROMs folder for every system.
Screens: Settings/TidyReportView
Acceptance:
- [unit] `MediaTidier` and `DuplicateFinder` work on a temp folder.
- [manual] Nothing moves before I approve.
Status: done

### S-042 Verify games against DATs
As the user, Tools › Verify Games checks a system's games against No-Intro and arcade DATs and can rename them to No-Intro's names.
Screens: Tools/VerifyReportView
Acceptance:
- [unit] `DATVerifier` and `ArcadeVerifier` report good, bad and unknown dumps.
- [unit] A copy whose right name is taken by the same dump goes to the Trash.
Status: done

### S-043 Rebuild arcade sets
As the user, Rebuild Sets makes arcade zips whole from loose files and other zips, and moves loose disc images into their set's folder.
Screens: Tools/SetRebuildReportView
Acceptance:
- [unit] `ArcadeRebuilder` builds a set from parts by CRC32.
- [manual] Each set's chips show the checksum they should have and mine.
Status: done

### S-044 Compress games
As the user, I compress disc games to CHD and others to ZIP from the Tools menu.
Screens: Tools/CompressReportView, Library/DiscImageSection
Acceptance:
- [unit] `CHDConversion` and `ROMZipping` produce files that verify.
Status: done

### S-045 Make disc playlists
As the user, Disc Playlists turns multi-disc games into one game with an .m3u; RetroBat's MultiDisc playlists work too.
Screens: Tools/DiscPlaylistReportView
Acceptance:
- [unit] `DiscPlaylists` groups discs; disc tracks aren't games.
Status: done

### S-046 Remove a system or some games
As the user, I remove a system from the library, or remove games by what they are, after a confirmation.
Screens: Library/RemoveSystem, Library/MultipleGames
Status: done

---

## M6 Cabinet Mode

Everything Cabinet Mode draws comes from `CabinetTheme`, so a theme creator
can edit it later. New visual settings go there, with defaults in the
built-in themes and a line in the Themes "Read Me.md".

### S-050 Open Cabinet Mode on the systems
As the user, I enter Cabinet Mode full screen and start on my systems, driven by the pad.
Screens: Cabinet/CabinetView, Cabinet/CabinetSystems
Acceptance:
- [unit] `GridNavigation` moves focus with the d-pad.
- [manual] Start opens the Cabinet menu.
Status: done

### S-051 Pick a theme and layout
As the user, I pick a theme (Showcase, Big Picture, Arcade, Apple TV, Carbon…) and a layout (carousel, grid, wheel, list, hero, cover flow, shelf, unboxed, cabinet).
Screens: Cabinet/CabinetLayouts, Settings/CabinetSettingsView
Acceptance:
- [unit] Every built-in theme decodes from theme.json and round-trips.
Status: done

### S-052 Open a game's page in Cabinet Mode
As the user, I open a game's page with its details, media, cartridge or disc, and play it.
Screens: Cabinet/CabinetGamePage
Status: done

### S-053 Search, sort and filter in Cabinet Mode
As the user, I search, sort, filter and jump to a random game with the pad.
Screens: Cabinet/CabinetSearch, Cabinet/CabinetMenu
Status: done

### S-054 Choose Cabinet Mode's display
As the user, I choose which display (including AirPlay) Cabinet Mode uses.
Screens: Cabinet/CabinetDisplay
Status: done

### S-055 Add cartridge, disc and mix to Game Art
As the user, I pick cartridge/disc, or a mix of 2D box, 3D box and medium, as a theme's Game Art.
Screens: Cabinet/CabinetLayouts, Settings/CabinetSettingsView
Depends: S-051
Acceptance:
- [unit] `CabinetTheme` Game Art gains `medium` and `mix` cases, and older theme.json files still decode.
- [snap] Each layout shows the cartridge or disc when chosen, and the box when a game has no medium image.
- [manual] The Themes "Read Me.md" documents the new values.
Status: built (needs a look in each layout)

### S-056 Show marquees on a second display
As the user with a real cabinet, the selected game's marquee shows on a second display while Cabinet Mode runs on the main one.
Screens: Cabinet/CabinetDisplay
Depends: S-054
Acceptance:
- [manual] Choosing a marquee display in Settings shows the system's logo, then the game's marquee as focus moves.
- [manual] Unplugging the second display doesn't stop Cabinet Mode.
- [unit] The marquee's fit and background come from `CabinetTheme`.
Status: todo

### S-057 Build a theme in a theme creator
As the user, I edit a Cabinet theme's colors, fonts, layout and art in a live editor and save it as a theme folder.
Screens: Settings/CabinetSettingsView
Depends: S-055, S-056
Acceptance:
- [manual] Every `CabinetTheme` setting can be changed and shows at once in a preview.
- [unit] A saved theme writes theme.json that loads back unchanged.
Status: todo

---

## M7 Several Macs and collections from elsewhere

### S-060 Sync play data between my Macs
As the user with several Macs, favorites, play time, last played, collections and saves follow me through iCloud Drive or a shared folder, applied only to games that Mac has.
Screens: Settings/GeneralSettingsView
Acceptance:
- [unit] Two stores merge by game identity (system + file name or checksum); the latest change wins per field.
- [unit] Data for a game this Mac doesn't have is kept, not dropped, and applied if the game shows up later.
- [manual] Saves don't overwrite a newer local save without a backup (S-019).
Status: todo

### S-061 Import media from a collection-style tree
As the user, Tools › Import Media understands trees like `collections/` with `medium_artwork/artwork_3d`, `medium_disc`, `medium_front` and `bezel_day`, and matches titles through the collection's `.dat`.
Screens: Tools/MediaImportReportView
Depends: S-024
Acceptance:
- [unit] Each folder maps to the right media kind; titles match through the `.dat`.
- [unit] Images convert to HEIC as Attic does elsewhere.
- [manual] The report lists what will be copied before anything is.
Status: todo

---

## Dropped

- Downloading or shipping BIOS files: Attic only checks the ones people provide.
- Accounts, sharing and social features: Attic is for one person's library.
- New Window: one library window is enough.
- Mix images and title screens as media kinds: retired in favor of covers, 3D boxes, logos and fan art.
