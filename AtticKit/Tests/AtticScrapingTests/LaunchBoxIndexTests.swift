import Foundation
import Testing
@testable import AtticScraping

struct LaunchBoxIndexTests {
    /// LaunchBox's Metadata.xml, Files.xml and Mame.xml in miniature.
    private func buildSample() throws -> (index: LaunchBoxIndex, summary: LaunchBoxIndexBuilder.Summary, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metadata = folder.appending(path: "Metadata.xml")
        try """
        <?xml version="1.0" standalone="yes"?>
        <LaunchBox>
          <Game>
            <Name>The Legend of Zelda: A Link to the Past</Name>
            <ReleaseDate>1992-04-13</ReleaseDate>
            <Overview>Link &amp; Zelda.</Overview>
            <MaxPlayers>1</MaxPlayers>
            <DatabaseID>10</DatabaseID>
            <CommunityRating>4.5</CommunityRating>
            <Platform>Super Nintendo Entertainment System</Platform>
            <Genres>Action; Adventure</Genres>
            <Developer>Nintendo</Developer>
            <Publisher>Nintendo</Publisher>
          </Game>
          <Game>
            <Name>Street Fighter II: The World Warrior</Name>
            <ReleaseYear>1991</ReleaseYear>
            <DatabaseID>20</DatabaseID>
            <Platform>Arcade</Platform>
          </Game>
          <Game>
            <Name>Halo</Name>
            <DatabaseID>30</DatabaseID>
            <Platform>Windows</Platform>
          </Game>
          <Platform>
            <Name>Arcade</Name>
          </Platform>
          <GameAlternateName>
            <AlternateName>Zelda no Densetsu: Kamigami no Triforce</AlternateName>
            <DatabaseID>10</DatabaseID>
          </GameAlternateName>
          <GameImage>
            <DatabaseID>10</DatabaseID>
            <FileName>41ba4239-f39b-4428-8568-4b09d46c23df.jpg</FileName>
            <Type>Box - Front</Type>
            <Region>Japan</Region>
          </GameImage>
          <GameImage>
            <DatabaseID>10</DatabaseID>
            <FileName>0a0b0c0d-0000-4000-8000-000000000001.png</FileName>
            <Type>Box - Front</Type>
            <Region>North America</Region>
          </GameImage>
          <GameImage>
            <DatabaseID>10</DatabaseID>
            <FileName>odd-name.png</FileName>
            <Type>Clear Logo</Type>
          </GameImage>
          <GameImage>
            <DatabaseID>10</DatabaseID>
            <FileName>0a0b0c0d-0000-4000-8000-000000000002.jpg</FileName>
            <Type>Advertisement Flyer - Front</Type>
          </GameImage>
          <GameImage>
            <DatabaseID>20</DatabaseID>
            <FileName>0a0b0c0d-0000-4000-8000-000000000004.jpg</FileName>
            <Type>Advertisement Flyer - Front</Type>
            <Region>World</Region>
          </GameImage>
          <GameImage>
            <DatabaseID>30</DatabaseID>
            <FileName>0a0b0c0d-0000-4000-8000-000000000003.jpg</FileName>
            <Type>Box - Front</Type>
          </GameImage>
        </LaunchBox>
        """.write(to: metadata, atomically: true, encoding: .utf8)
        let files = folder.appending(path: "Files.xml")
        try """
        <?xml version="1.0" standalone="yes"?>
        <LaunchBox>
          <File>
            <Platform>Super Nintendo Entertainment System</Platform>
            <FileName>Zelda no Densetsu - Kamigami no Triforce (Japan)</FileName>
            <GameName>The Legend of Zelda: A Link to the Past</GameName>
          </File>
        </LaunchBox>
        """.write(to: files, atomically: true, encoding: .utf8)
        let mame = folder.appending(path: "Mame.xml")
        try """
        <?xml version="1.0" standalone="yes"?>
        <LaunchBox>
          <MameFile>
            <FileName>sf2</FileName>
            <Name>Street Fighter II: The World Warrior</Name>
          </MameFile>
        </LaunchBox>
        """.write(to: mame, atomically: true, encoding: .utf8)

        let destination = folder.appending(path: "launchbox.sqlite")
        let summary = try LaunchBoxIndexBuilder.build(metadata: metadata, files: files, mame: mame,
                                                      platforms: ["Super Nintendo Entertainment System", "Arcade"], to: destination)
        return (try LaunchBoxIndex(contentsOf: destination), summary, folder)
    }

    @Test func keepsOnlyTheChosenPlatformsAndKindsOfPicture() throws {
        let (index, summary, folder) = try buildSample()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(summary == .init(games: 2, images: 5))
        #expect(index.gameCount == 2)
        #expect(index.info(for: .init(fileName: "Halo", platforms: ["Windows"])) == nil)
    }

    @Test func findsAGameByItsNoIntroNameAndTakesItsFacts() throws {
        let (index, _, folder) = try buildSample()
        defer { try? FileManager.default.removeItem(at: folder) }
        let info = try #require(index.info(for: .init(fileName: "Legend of Zelda, The - A Link to the Past (USA)",
                                                      platforms: ["Super Nintendo Entertainment System"])))
        #expect(info.title == "The Legend of Zelda: A Link to the Past")
        #expect(info.description == "Link & Zelda.")
        #expect(info.genre == "Action, Adventure")
        #expect(info.players == "1")
        #expect(info.rating == 0.9)
        #expect(info.developer == "Nintendo")
        // The North American box for a USA file, the logo whatever its name.
        #expect(info.coverArtURL?.absoluteString == "https://images.launchbox-app.com/0a0b0c0d-0000-4000-8000-000000000001.png")
        #expect(info.logoURL?.absoluteString == "https://images.launchbox-app.com/odd-name.png")
        #expect(info.screenshotURL == nil)
    }

    @Test func aJapaneseFileGetsTheJapaneseBox() throws {
        let (index, _, folder) = try buildSample()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Matched through Files.xml, by a name LaunchBox gives the file.
        let info = try #require(index.info(for: .init(fileName: "Zelda no Densetsu - Kamigami no Triforce (Japan)",
                                                      platforms: ["Super Nintendo Entertainment System"])))
        #expect(info.coverArtURL?.lastPathComponent == "41ba4239-f39b-4428-8568-4b09d46c23df.jpg")
    }

    @Test func anArcadeSetIsFoundByItsShortName() throws {
        let (index, _, folder) = try buildSample()
        defer { try? FileManager.default.removeItem(at: folder) }
        let info = try #require(index.info(for: .init(fileName: "sf2", platforms: ["Arcade"])))
        #expect(info.title == "Street Fighter II: The World Warrior")
        #expect(info.releaseDate == LaunchBoxIndex.releaseDate("1991"))
        // No box: its flyer is its cover.
        #expect(info.coverArtURL?.lastPathComponent == "0a0b0c0d-0000-4000-8000-000000000004.jpg")
        // Not on the system's platforms: not found.
        #expect(index.info(for: .init(fileName: "sf2", platforms: ["Super Nintendo Entertainment System"])) == nil)
    }

    @Test func namesCompareWithoutTagsArticlesOrPunctuation() {
        #expect(LaunchBoxIndex.key("Legend of Zelda, The - A Link to the Past") == LaunchBoxIndex.key("The Legend of Zelda: A Link to the Past"))
        #expect(LaunchBoxIndex.key("Pokémon Pinball") == "pokemonpinball")
        #expect(LaunchBoxIndex.key("Tom & Jerry") == "tomandjerry")
        #expect(LaunchBoxIndex.stripTags("Sonic (USA) (Rev 1) [!]") == "Sonic")
        #expect(LaunchBoxIndex.region(ofFileName: "Sonic (Japan, USA)") == "Japan")
        #expect(LaunchBoxIndex.region(ofFileName: "Sonic (En,Fr) (Europe)") == "Europe")
    }
}
