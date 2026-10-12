import Foundation
import Testing
@testable import AtticLibraryScanning
@testable import AtticModels

@Suite struct LibraryScannerTests {

    /// A `LibraryScanner` whose `ESDELibraryImporter` is pointed at an
    /// isolated, empty "home directory" rather than the real one — on the
    /// machine these tests were developed on, `~/ES-DE/gamelists` has real
    /// scraped data for most MVP system short names, which would otherwise
    /// make fixtures using realistic names ("nes", "snes", "psx", "gba")
    /// pass or fail based on that ambient state instead of the fixture
    /// itself being exercised.
    private func isolatedScanner() throws -> LibraryScanner {
        let fakeHome = FileManager.default.temporaryDirectory
            .appending(path: "attic-scanner-isolated-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        return LibraryScanner(importers: [ESDELibraryImporter(homeDirectoryURL: fakeHome), BatoceraLibraryImporter()])
    }

    /// Builds two entirely separate roots (not sibling "ROMs"/"roms" under
    /// one parent — those collide into the same directory on the default
    /// case-insensitive APFS volume): an ES-DE-style ROMs root containing a
    /// fully-scraped `snes` system, an unrecognized folder name, a
    /// genuinely-empty (still undetected) `psx` folder, a populated-but-
    /// unscraped `gba` folder (no gamelist.xml/downloaded_media at all —
    /// confirmed against a real ES-DE library, this is still picked up via
    /// the bare-file fallback rather than skipped), and a Batocera-style
    /// root containing a recognized `nes` system.
    private func makeMixedRoot() throws -> (esdeRomsRoot: URL, batoceraRomsRoot: URL) {
        let fm = FileManager.default
        let esdeParent = fm.temporaryDirectory.appending(path: "attic-scanner-esde-\(UUID().uuidString)", directoryHint: .isDirectory)
        let batoceraParent = fm.temporaryDirectory.appending(path: "attic-scanner-batocera-\(UUID().uuidString)", directoryHint: .isDirectory)

        let esdeRomsRoot = esdeParent.appending(path: "ROMs")
        let snesFolder = esdeRomsRoot.appending(path: "snes")
        try fm.createDirectory(at: snesFolder, withIntermediateDirectories: true)
        try Data().write(to: snesFolder.appending(path: "Super Metroid.sfc"))
        let gamelistDir = esdeParent.appending(path: "ES-DE/gamelists/snes")
        try fm.createDirectory(at: gamelistDir, withIntermediateDirectories: true)
        try """
        <?xml version="1.0"?>
        <gameList>
          <game><path>./Super Metroid.sfc</path><name>Super Metroid</name></game>
        </gameList>
        """.write(to: gamelistDir.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)

        let unknownFolder = esdeRomsRoot.appending(path: "totally-unknown-system")
        try fm.createDirectory(at: unknownFolder, withIntermediateDirectories: true)

        let undetectedPSXFolder = esdeRomsRoot.appending(path: "psx")
        try fm.createDirectory(at: undetectedPSXFolder, withIntermediateDirectories: true)

        let unscrapedGBAFolder = esdeRomsRoot.appending(path: "gba")
        try fm.createDirectory(at: unscrapedGBAFolder, withIntermediateDirectories: true)
        try Data().write(to: unscrapedGBAFolder.appending(path: "Metroid Fusion.gba"))
        try Data().write(to: unscrapedGBAFolder.appending(path: "systeminfo.txt"))

        let hiddenFolder = esdeRomsRoot.appending(path: ".DS_Store")
        try Data().write(to: hiddenFolder)

        let batoceraRomsRoot = batoceraParent.appending(path: "roms")
        let nesFolder = batoceraRomsRoot.appending(path: "nes")
        try fm.createDirectory(at: nesFolder, withIntermediateDirectories: true)
        try "<gameList><game><path>./Mario.nes</path><name>Mario</name></game></gameList>"
            .write(to: nesFolder.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)

        return (esdeRomsRoot, batoceraRomsRoot)
    }

    @Test func scanRecognizesESDESystemsIncludingUnscrapedAndSkipsUnrecognizedAndUndetectedFolders() throws {
        let (esdeRoot, _) = try makeMixedRoot()
        let result = try isolatedScanner().scan(romsRootURL: esdeRoot)

        #expect(result.systems.count == 2)
        let snes = try #require(result.systems.first { $0.canonicalID == .snes })
        #expect(snes.libraryFormat == .esde)
        #expect(snes.games.map(\.title) == ["Super Metroid"])

        let gba = try #require(result.systems.first { $0.canonicalID == .gba })
        #expect(gba.libraryFormat == .esde)
        // Bare fallback: filename-derived title, systeminfo.txt excluded.
        #expect(gba.games.map(\.romRelativePath) == ["Metroid Fusion.gba"])

        #expect(result.issues.contains { $0.folderURL.lastPathComponent == "totally-unknown-system" && $0.reason == .unrecognizedSystemFolderName })
        #expect(result.issues.contains { $0.folderURL.lastPathComponent == "psx" && $0.reason == .noImporterRecognizedFormat })
        // .DS_Store is a file, not a directory, and must not appear as an issue at all.
        #expect(result.issues.allSatisfy { $0.folderURL.lastPathComponent != ".DS_Store" })
    }

    @Test func scanRecognizesBatoceraSystem() throws {
        let (_, batoceraRoot) = try makeMixedRoot()
        let result = try isolatedScanner().scan(romsRootURL: batoceraRoot)

        #expect(result.systems.count == 1)
        #expect(result.systems.first?.canonicalID == .nes)
        #expect(result.systems.first?.libraryFormat == .batocera)
        #expect(result.issues.isEmpty)
    }

    @Test func scanningMultipleRootsMergesResults() throws {
        let (esdeRoot, batoceraRoot) = try makeMixedRoot()
        let result = try isolatedScanner().scan(romsRootURLs: [esdeRoot, batoceraRoot])

        let canonicalIDs = Set(result.systems.map(\.canonicalID))
        #expect(canonicalIDs == [.snes, .gba, .nes])
    }

    @Test func scanOfNonexistentRootReturnsEmptyResultWithoutThrowing() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "attic-does-not-exist-\(UUID().uuidString)")
        let result = try isolatedScanner().scan(romsRootURL: missing)

        #expect(result.systems.isEmpty)
        #expect(result.issues.isEmpty)
    }

    @Test func rescanningTheSameRootIsIdempotentAtTheDTOLevel() throws {
        let (esdeRoot, _) = try makeMixedRoot()
        let scanner = try isolatedScanner()
        let first = scanner.scan(romsRootURL: esdeRoot)
        let second = scanner.scan(romsRootURL: esdeRoot)

        #expect(first.systems.map(\.canonicalID) == second.systems.map(\.canonicalID))
        #expect(first.systems.first?.games.count == second.systems.first?.games.count)
    }
}
