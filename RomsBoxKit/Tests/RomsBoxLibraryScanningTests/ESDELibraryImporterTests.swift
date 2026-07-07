import Foundation
import Testing
@testable import RomsBoxLibraryScanning
@testable import RomsBoxModels

@Suite struct ESDELibraryImporterTests {

    private let snesGamelist = """
    <?xml version="1.0"?>
    <gameList>
      <game>
        <path>./Super Metroid.sfc</path>
        <name>Super Metroid</name>
        <desc>A classic Metroidvania.</desc>
        <releasedate>19940318T000000</releasedate>
        <developer>Nintendo</developer>
        <rating>0.95</rating>
        <favorite>true</favorite>
      </game>
    </gameList>
    """

    /// Builds `<root>/ROMs/<system>/...` + `<root>/ES-DE/{gamelists,downloaded_media}/<system>/...`
    /// — the default ES-DE install layout, where ES-DE's app data tree is a
    /// sibling of the ROMs root rather than nested inside a system folder.
    private func makeESDERoot(
        systemName: String = "snes",
        includeGamelist: Bool = true,
        includeMedia: Bool = true
    ) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "romsbox-esde-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let romsSystemFolder = root.appending(path: "ROMs").appending(path: systemName)
        try fm.createDirectory(at: romsSystemFolder, withIntermediateDirectories: true)
        try Data().write(to: romsSystemFolder.appending(path: "Super Metroid.sfc"))
        try Data().write(to: romsSystemFolder.appending(path: "Chrono Trigger.sfc"))

        if includeGamelist {
            let gamelistDir = root.appending(path: "ES-DE/gamelists").appending(path: systemName)
            try fm.createDirectory(at: gamelistDir, withIntermediateDirectories: true)
            try snesGamelist.write(to: gamelistDir.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)
        }

        if includeMedia {
            let mediaRoot = root.appending(path: "ES-DE/downloaded_media").appending(path: systemName)
            for type in ["miximages", "covers", "titlescreens", "videos"] {
                try fm.createDirectory(at: mediaRoot.appending(path: type), withIntermediateDirectories: true)
            }
            try Data().write(to: mediaRoot.appending(path: "miximages/Super Metroid.png"))
            try Data().write(to: mediaRoot.appending(path: "covers/Super Metroid.png"))
            try Data().write(to: mediaRoot.appending(path: "covers/Chrono Trigger.png"))
            try Data().write(to: mediaRoot.appending(path: "titlescreens/Super Metroid.png"))
            try Data().write(to: mediaRoot.appending(path: "videos/Super Metroid.mp4"))
        }

        return romsSystemFolder
    }

    /// Builds `<root>/ROMs/<system>/...` + `<root>/downloaded_media/<system>/...`
    /// with NO `ES-DE/` wrapper folder — media is a direct sibling of ROMs.
    /// Confirmed against a real user ES-DE library configured this way
    /// (custom "app data directory" pointed at the same parent as ROMs).
    private func makeFlatESDERoot(systemName: String = "snes") throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "romsbox-esde-flat-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let romsSystemFolder = root.appending(path: "ROMs").appending(path: systemName)
        try fm.createDirectory(at: romsSystemFolder, withIntermediateDirectories: true)
        try Data().write(to: romsSystemFolder.appending(path: "Super Metroid.sfc"))

        let mediaRoot = root.appending(path: "downloaded_media").appending(path: systemName)
        try fm.createDirectory(at: mediaRoot.appending(path: "covers"), withIntermediateDirectories: true)
        try Data().write(to: mediaRoot.appending(path: "covers/Super Metroid.png"))

        return romsSystemFolder
    }

    @Test func detectReturnsTrueWhenGamelistExistsInSiblingESDETree() throws {
        let folder = try makeESDERoot()
        #expect(ESDELibraryImporter().detect(systemFolderURL: folder))
    }

    @Test func detectReturnsTrueForFlatLayoutWithNoESDEWrapperFolder() throws {
        let folder = try makeFlatESDERoot()
        #expect(ESDELibraryImporter().detect(systemFolderURL: folder))
    }

    @Test func resolvesCoverArtInFlatLayoutWithNoESDEWrapperFolder() throws {
        let folder = try makeFlatESDERoot()
        let data = try ESDELibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)
        let metroid = try #require(data.games.first { $0.romRelativePath == "Super Metroid.sfc" })
        #expect(metroid.coverArtURL?.lastPathComponent == "Super Metroid.png")
    }

    @Test func detectReturnsTrueWhenOnlyDownloadedMediaExists() throws {
        let folder = try makeESDERoot(includeGamelist: false, includeMedia: true)
        #expect(ESDELibraryImporter().detect(systemFolderURL: folder))
    }

    /// Confirmed against a real ES-DE library: a system folder can be
    /// entirely unscraped (no gamelist.xml or downloaded_media exist
    /// anywhere for it) while still containing real ROM files — ES-DE
    /// itself still lists those, so RomsBox should too rather than silently
    /// hiding a populated system neither convention has positively claimed.
    @Test func detectReturnsTrueForPopulatedButEntirelyUnscrapedFolder() throws {
        let folder = try makeESDERoot(includeGamelist: false, includeMedia: false)
        #expect(ESDELibraryImporter().detect(systemFolderURL: folder))
    }

    @Test func detectReturnsFalseForACompletelyEmptyFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "romsbox-esde-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(ESDELibraryImporter().detect(systemFolderURL: root) == false)
    }

    @Test func detectReturnsFalseWhenOnlyASystemInfoFileIsPresent() throws {
        // ES-DE auto-generates systeminfo.txt in every system folder,
        // scraped or not — its mere presence must not count as "has ROMs".
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "romsbox-esde-systeminfo-only-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "systeminfo.txt"))
        #expect(ESDELibraryImporter().detect(systemFolderURL: root) == false)
    }

    @Test func systemInfoFileIsNotImportedAsABareGame() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "romsbox-esde-systeminfo-plus-rom-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "systeminfo.txt"))
        try Data().write(to: root.appending(path: "Sonic the Hedgehog.md"))

        let data = try ESDELibraryImporter().importSystem(systemFolderURL: root, canonicalID: .genesis)
        #expect(data.games.count == 1)
        #expect(data.games.first?.romRelativePath == "Sonic the Hedgehog.md")
    }

    @Test func importParsesScrapedGameFromGamelist() throws {
        let folder = try makeESDERoot()
        let data = try ESDELibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)

        #expect(data.canonicalID == .snes)
        #expect(data.libraryFormat == .esde)

        let metroid = try #require(data.games.first { $0.title == "Super Metroid" })
        #expect(metroid.romRelativePath == "Super Metroid.sfc")
        #expect(metroid.description == "A classic Metroidvania.")
        #expect(metroid.developer == "Nintendo")
        #expect(metroid.rating == 0.95)
        #expect(metroid.favorite == true)
    }

    @Test func coverArtPrefersMiximageOverCover() throws {
        let folder = try makeESDERoot()
        let data = try ESDELibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)
        let metroid = try #require(data.games.first { $0.title == "Super Metroid" })

        let expectedMiximage = ESDELibraryImporter.esdeRootURL(forSystemFolderURL: folder)
            .appending(path: "downloaded_media/snes/miximages/Super Metroid.png")
        #expect(metroid.coverArtURL == expectedMiximage)
    }

    @Test func resolvesTitleScreenAndVideoByFilename() throws {
        let folder = try makeESDERoot()
        let data = try ESDELibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)
        let metroid = try #require(data.games.first { $0.title == "Super Metroid" })

        #expect(metroid.titleScreenURL?.lastPathComponent == "Super Metroid.png")
        #expect(metroid.videoURL?.lastPathComponent == "Super Metroid.mp4")
    }

    @Test func unscrapedROMFallsBackToBareRecordWithFilenameTitle() throws {
        let folder = try makeESDERoot()
        let data = try ESDELibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)

        #expect(data.games.count == 2)
        let chrono = try #require(data.games.first { $0.romRelativePath == "Chrono Trigger.sfc" })
        #expect(chrono.title == "Chrono Trigger")
        #expect(chrono.coverArtURL?.lastPathComponent == "Chrono Trigger.png")
        #expect(chrono.description == nil)
    }

    @Test func importWithNoGamelistFallsBackEntirelyToBareRecords() throws {
        let folder = try makeESDERoot(includeGamelist: false, includeMedia: true)
        let data = try ESDELibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)

        #expect(data.games.count == 2)
        #expect(data.games.allSatisfy { $0.description == nil })
    }

    // MARK: - Mixed-root auto-detection

    @Test func esdeAndBatoceraImportersCorrectlyDiscriminateSiblingSystemFolders() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "romsbox-mixed-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)

        // snes: ES-DE convention (ROMs/snes + sibling ES-DE/ tree).
        let snesFolder = root.appending(path: "ROMs/snes")
        try fm.createDirectory(at: snesFolder, withIntermediateDirectories: true)
        try Data().write(to: snesFolder.appending(path: "Super Metroid.sfc"))
        let gamelistDir = root.appending(path: "ES-DE/gamelists/snes")
        try fm.createDirectory(at: gamelistDir, withIntermediateDirectories: true)
        try snesGamelist.write(to: gamelistDir.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)

        // nes: Batocera convention (roms/nes/gamelist.xml colocated with ROMs).
        let nesFolder = root.appending(path: "roms/nes")
        try fm.createDirectory(at: nesFolder, withIntermediateDirectories: true)
        try "<gameList><game><path>./Mario.nes</path><name>Mario</name></game></gameList>"
            .write(to: nesFolder.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)

        let esde = ESDELibraryImporter()
        let batocera = BatoceraLibraryImporter()

        #expect(esde.detect(systemFolderURL: snesFolder) == true)
        #expect(batocera.detect(systemFolderURL: snesFolder) == false)

        #expect(batocera.detect(systemFolderURL: nesFolder) == true)
        #expect(esde.detect(systemFolderURL: nesFolder) == false)
    }
}
