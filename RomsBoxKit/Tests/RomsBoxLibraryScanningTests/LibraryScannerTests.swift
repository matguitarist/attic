import Foundation
import Testing
@testable import RomsBoxLibraryScanning
@testable import RomsBoxModels

@Suite struct LibraryScannerTests {

    /// Builds two entirely separate roots (not sibling "ROMs"/"roms" under
    /// one parent — those collide into the same directory on the default
    /// case-insensitive APFS volume): an ES-DE-style ROMs root containing a
    /// recognized `snes` system, an unrecognized folder name, and a
    /// recognized-but-undetected `psx` folder; and a Batocera-style root
    /// containing a recognized `nes` system.
    private func makeMixedRoot() throws -> (esdeRomsRoot: URL, batoceraRomsRoot: URL) {
        let fm = FileManager.default
        let esdeParent = fm.temporaryDirectory.appending(path: "romsbox-scanner-esde-\(UUID().uuidString)", directoryHint: .isDirectory)
        let batoceraParent = fm.temporaryDirectory.appending(path: "romsbox-scanner-batocera-\(UUID().uuidString)", directoryHint: .isDirectory)

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
        try Data().write(to: undetectedPSXFolder.appending(path: "Final Fantasy VII.bin"))

        let hiddenFolder = esdeRomsRoot.appending(path: ".DS_Store")
        try Data().write(to: hiddenFolder)

        let batoceraRomsRoot = batoceraParent.appending(path: "roms")
        let nesFolder = batoceraRomsRoot.appending(path: "nes")
        try fm.createDirectory(at: nesFolder, withIntermediateDirectories: true)
        try "<gameList><game><path>./Mario.nes</path><name>Mario</name></game></gameList>"
            .write(to: nesFolder.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)

        return (esdeRomsRoot, batoceraRomsRoot)
    }

    @Test func scanRecognizesESDESystemAndSkipsUnrecognizedAndUndetectedFolders() throws {
        let (esdeRoot, _) = try makeMixedRoot()
        let result = LibraryScanner().scan(romsRootURL: esdeRoot)

        #expect(result.systems.count == 1)
        #expect(result.systems.first?.canonicalID == .snes)
        #expect(result.systems.first?.libraryFormat == .esde)

        #expect(result.issues.contains { $0.folderURL.lastPathComponent == "totally-unknown-system" && $0.reason == .unrecognizedSystemFolderName })
        #expect(result.issues.contains { $0.folderURL.lastPathComponent == "psx" && $0.reason == .noImporterRecognizedFormat })
        // .DS_Store is a file, not a directory, and must not appear as an issue at all.
        #expect(result.issues.allSatisfy { $0.folderURL.lastPathComponent != ".DS_Store" })
    }

    @Test func scanRecognizesBatoceraSystem() throws {
        let (_, batoceraRoot) = try makeMixedRoot()
        let result = LibraryScanner().scan(romsRootURL: batoceraRoot)

        #expect(result.systems.count == 1)
        #expect(result.systems.first?.canonicalID == .nes)
        #expect(result.systems.first?.libraryFormat == .batocera)
        #expect(result.issues.isEmpty)
    }

    @Test func scanningMultipleRootsMergesResults() throws {
        let (esdeRoot, batoceraRoot) = try makeMixedRoot()
        let result = LibraryScanner().scan(romsRootURLs: [esdeRoot, batoceraRoot])

        let canonicalIDs = Set(result.systems.map(\.canonicalID))
        #expect(canonicalIDs == [.snes, .nes])
    }

    @Test func scanOfNonexistentRootReturnsEmptyResultWithoutThrowing() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "romsbox-does-not-exist-\(UUID().uuidString)")
        let result = LibraryScanner().scan(romsRootURL: missing)

        #expect(result.systems.isEmpty)
        #expect(result.issues.isEmpty)
    }

    @Test func rescanningTheSameRootIsIdempotentAtTheDTOLevel() throws {
        let (esdeRoot, _) = try makeMixedRoot()
        let scanner = LibraryScanner()
        let first = scanner.scan(romsRootURL: esdeRoot)
        let second = scanner.scan(romsRootURL: esdeRoot)

        #expect(first.systems.map(\.canonicalID) == second.systems.map(\.canonicalID))
        #expect(first.systems.first?.games.count == second.systems.first?.games.count)
    }
}
