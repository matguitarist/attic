import Foundation
import Testing
@testable import RomsBoxLibraryScanning

@Suite struct GamelistXMLFieldParserTests {

    @Test func parsesAWellFormedSingleRootGamelist() throws {
        let xml = """
        <?xml version="1.0"?>
        <gameList>
          <game><path>./Mario.nes</path><name>Mario</name></game>
        </gameList>
        """
        let games = try GamelistXMLFieldParser().parse(Data(xml.utf8))
        #expect(games.count == 1)
        #expect(games.first?["name"] == "Mario")
    }

    /// Regression test: some real ES-DE gamelist.xml files have a sibling
    /// `<alternativeEmulator>` element *before* `<gameList>`, which makes
    /// the file not a single well-formed XML document with one root.
    /// Confirmed against a real, otherwise-valid 789-game SNES gamelist.xml
    /// that Foundation's XMLParser rejected outright ("junk after document
    /// element") before this fix — ES-DE's own parser evidently tolerates
    /// the same file.
    @Test func parsesGamelistWithLeadingAlternativeEmulatorPreamble() throws {
        let xml = """
        <?xml version="1.0"?>
        <alternativeEmulator>
        \t<label>bsnes-hd</label>
        </alternativeEmulator>
        <gameList>
          <game><path>./7th Saga, The (USA).zip</path><name>The 7th Saga</name></game>
        </gameList>
        """
        let games = try GamelistXMLFieldParser().parse(Data(xml.utf8))
        #expect(games.count == 1)
        #expect(games.first?["name"] == "The 7th Saga")
    }

    @Test func genuinelyMalformedXMLStillThrows() {
        let xml = "<gameList><game><path>unterminated"
        #expect(throws: (any Error).self) {
            try GamelistXMLFieldParser().parse(Data(xml.utf8))
        }
    }
}
