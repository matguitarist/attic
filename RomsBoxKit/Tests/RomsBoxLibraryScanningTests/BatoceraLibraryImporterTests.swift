import Foundation
import Testing
@testable import RomsBoxLibraryScanning
@testable import RomsBoxModels

@Suite struct BatoceraLibraryImporterTests {

    /// Builds a throwaway on-disk Batocera-style system folder
    /// (`gamelist.xml` next to the ROMs) and returns its URL.
    private func makeSystemFolder(gamelistXML: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "romsbox-batocera-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try gamelistXML.write(to: root.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)
        return root
    }

    private let nesGamelist = """
    <?xml version="1.0"?>
    <gameList>
      <game>
        <path>./Super Mario Bros.nes</path>
        <name>Super Mario Bros.</name>
        <desc>A classic platformer.</desc>
        <image>./media/images/Super Mario Bros-image.png</image>
        <releasedate>19850913T000000</releasedate>
        <developer>Nintendo</developer>
        <publisher>Nintendo</publisher>
        <genre>Platform</genre>
        <players>1-2</players>
        <rating>0.9</rating>
        <favorite>true</favorite>
      </game>
      <game>
        <path>./Duck Hunt.nes</path>
        <name>Duck Hunt</name>
      </game>
      <game>
        <name>Missing Path Game (should be skipped)</name>
      </game>
    </gameList>
    """

    private let snesGamelist = """
    <?xml version="1.0"?>
    <gameList>
      <game>
        <path>./Super Metroid.sfc</path>
        <name>Super Metroid</name>
        <image>~/.emulationstation/downloaded_images/snes/Super Metroid-image.png</image>
        <video>/Users/tester/videos/Super Metroid.mp4</video>
        <releasedate>19940318T000000</releasedate>
      </game>
    </gameList>
    """

    @Test func detectReturnsTrueWhenGamelistXMLIsPresent() throws {
        let folder = try makeSystemFolder(gamelistXML: nesGamelist)
        #expect(BatoceraLibraryImporter().detect(systemFolderURL: folder))
    }

    @Test func detectReturnsFalseWhenGamelistXMLIsAbsent() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "romsbox-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(BatoceraLibraryImporter().detect(systemFolderURL: folder) == false)
    }

    @Test func importsGamesAndSkipsEntriesMissingAPath() throws {
        let folder = try makeSystemFolder(gamelistXML: nesGamelist)
        let data = try BatoceraLibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .nes)

        #expect(data.canonicalID == .nes)
        #expect(data.libraryFormat == .batocera)
        #expect(data.games.count == 2)
    }

    @Test func parsesFullyPopulatedGameEntry() throws {
        let folder = try makeSystemFolder(gamelistXML: nesGamelist)
        let data = try BatoceraLibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .nes)
        let mario = try #require(data.games.first { $0.title == "Super Mario Bros." })

        #expect(mario.romRelativePath == "Super Mario Bros.nes")
        #expect(mario.description == "A classic platformer.")
        #expect(mario.developer == "Nintendo")
        #expect(mario.publisher == "Nintendo")
        #expect(mario.genre == "Platform")
        #expect(mario.players == "1-2")
        #expect(mario.rating == 0.9)
        #expect(mario.favorite == true)
        #expect(mario.coverArtURL == folder.appending(path: "media/images/Super Mario Bros-image.png"))

        var expectedComponents = DateComponents()
        expectedComponents.year = 1985
        expectedComponents.month = 9
        expectedComponents.day = 13
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let expectedDate = calendar.date(from: expectedComponents)
        #expect(mario.releaseDate == expectedDate)
    }

    @Test func parsesMinimalGameEntryWithOptionalFieldsNil() throws {
        let folder = try makeSystemFolder(gamelistXML: nesGamelist)
        let data = try BatoceraLibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .nes)
        let duckHunt = try #require(data.games.first { $0.title == "Duck Hunt" })

        #expect(duckHunt.romRelativePath == "Duck Hunt.nes")
        #expect(duckHunt.description == nil)
        #expect(duckHunt.rating == nil)
        #expect(duckHunt.favorite == false)
        #expect(duckHunt.coverArtURL == nil)
    }

    @Test func resolvesTildePrefixedMediaPath() throws {
        let folder = try makeSystemFolder(gamelistXML: snesGamelist)
        let data = try BatoceraLibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)
        let metroid = try #require(data.games.first)

        let expectedExpandedPath = ("~/.emulationstation/downloaded_images/snes/Super Metroid-image.png" as NSString)
            .expandingTildeInPath
        #expect(metroid.coverArtURL == URL(fileURLWithPath: expectedExpandedPath))
    }

    @Test func resolvesAbsoluteMediaPath() throws {
        let folder = try makeSystemFolder(gamelistXML: snesGamelist)
        let data = try BatoceraLibraryImporter().importSystem(systemFolderURL: folder, canonicalID: .snes)
        let metroid = try #require(data.games.first)

        #expect(metroid.videoURL == URL(fileURLWithPath: "/Users/tester/videos/Super Metroid.mp4"))
    }
}
