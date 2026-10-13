import Foundation
import Testing
@testable import AtticLibraryScanning
@testable import AtticModels

struct ArcadeNameIndexTests {
    private static let dat = Data("""
    <?xml version="1.0"?>
    <!DOCTYPE datafile PUBLIC "-//FinalBurn Neo//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
    <datafile>
        <header><name>FinalBurn Neo - Arcade Games</name><description>Header</description></header>
        <game name="mslug" romof="neogeo">
            <description>Metal Slug - Super Vehicle-001</description>
            <year>1996</year>
            <manufacturer>Nazca</manufacturer>
            <rom name="201-p1.p1" size="2097152" crc="08d8daa5"/>
        </game>
        <game name="2020bb" romof="neogeo">
            <description>2020 Super Baseball (set 1)</description>
            <year>199?</year>
            <manufacturer>SNK / Pallas</manufacturer>
        </game>
    </datafile>
    """.utf8)

    @Test func parsesTitlesYearsAndManufacturers() throws {
        let index = try #require(ArcadeNameIndex.parse(dat: Self.dat))
        #expect(index["mslug"] == .init(title: "Metal Slug - Super Vehicle-001", year: 1996, manufacturer: "Nazca"))
        // "(set 1)" dropped; an unknown year ("199?") is left out.
        #expect(index["2020BB"] == .init(title: "2020 Super Baseball", year: nil, manufacturer: "SNK / Pallas"))
        #expect(index.entries.count == 2)
    }

    @Test func trailingVersionTagsAreDropped() {
        #expect(ArcadeNameIndex.cleanedTitle("1941: Counter Attack (World 900227)") == "1941: Counter Attack")
        #expect(ArcadeNameIndex.cleanedTitle("Mega Man: The Power Battle (CPS1, USA 951006)") == "Mega Man: The Power Battle")
        #expect(ArcadeNameIndex.cleanedTitle("Art of Fighting 2 / Ryuuko no Ken 2 (NGM-056) [bootleg]") == "Art of Fighting 2 / Ryuuko no Ken 2")
        #expect(ArcadeNameIndex.cleanedTitle("(prototype)") == "(prototype)")
    }

    @Test func namesOnlyGamesTheImporterNamedAfterTheirFile() throws {
        let index = try #require(ArcadeNameIndex.parse(dat: Self.dat))
        let system = ImportedSystemData(
            canonicalID: .neogeo,
            libraryFormat: .esde,
            romsRootURL: URL(fileURLWithPath: "/ROMs/neogeo"),
            games: [
                ImportedGameRecord(romRelativePath: "mslug.zip", title: ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: "mslug.zip")),
                ImportedGameRecord(romRelativePath: "2020bb.zip", title: "Super Baseball 2020", developer: "SNK"),
                ImportedGameRecord(romRelativePath: "unknown.zip", title: ROMFilenameTitleCleaner.cleanTitle(fromROMFilename: "unknown.zip"))
            ]
        )

        let named = index.applying(to: system).games
        #expect(named[0].title == "Metal Slug - Super Vehicle-001")
        #expect(named[0].developer == "Nazca")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(named[0].releaseDate.map { utc.component(.year, from: $0) } == 1996)
        #expect(named[1] == system.games[1], "gamelist.xml names win")
        #expect(named[2] == system.games[2])
    }

    @Test func loadUsesAFreshCacheAndRebuildsAStaleOne() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appending(path: "ArcadeNames-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let first = await ArcadeNameIndex.load(cacheURL: cacheURL) { Self.dat }
        #expect(first?["mslug"] != nil)

        // Fresh cache: the DAT isn't fetched again.
        let cached = await ArcadeNameIndex.load(cacheURL: cacheURL) { throw URLError(.notConnectedToInternet) }
        #expect(cached == first)

        // Stale cache and offline: the stale copy is still used.
        let offline = await ArcadeNameIndex.load(cacheURL: cacheURL, maxAge: 0) { throw URLError(.notConnectedToInternet) }
        #expect(offline == first)
    }

    @Test func readsESDEsMAMENames() throws {
        let xml = """
        <!-- Generated from MAME driver file mame0289.xml -->
        <game>
        \t<mamename>vf4</mamename>
        \t<realname>Virtua Fighter 4 Version C (GDS-0012C)</realname>
        </game>
        <game>
        \t<mamename>vf4evo</mamename>
        \t<realname>Virtua Fighter 4: Evolution (Version B) (Japan) (GDS-0024C)</realname>
        </game>
        """
        // As ES-DE ships it: no root element.
        let index = try #require(ArcadeNameIndex.parse(dat: Data(xml.utf8)))
        #expect(index["VF4"]?.title == "Virtua Fighter 4 Version C")
        #expect(index["vf4evo"]?.title == "Virtua Fighter 4: Evolution")
        #expect(index["vf4"]?.year == nil)
    }

    @Test func finalBurnNeosNamesComeFirst() {
        let fbneo = ArcadeNameIndex(entries: ["mslug": .init(title: "Metal Slug", year: 1996, manufacturer: "Nazca")])
        let mame = ArcadeNameIndex(entries: ["mslug": .init(title: "Metal Slug (MAME)", year: nil, manufacturer: nil),
                                             "vf4": .init(title: "Virtua Fighter 4", year: nil, manufacturer: nil)])
        let both = fbneo.adding(mame)
        #expect(both["mslug"]?.year == 1996)
        #expect(both["vf4"]?.title == "Virtua Fighter 4")
    }
}
