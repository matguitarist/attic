import Foundation
import Testing
@testable import RomsBoxScraping

@Suite struct ScreenScraperMapperTests {
    /// Hand-built fixture matching the region/language-array shape
    /// documented by existing open-source ScreenScraper API clients.
    private let fullFixture = """
    {
      "response": {
        "jeu": {
          "noms": [
            {"region": "jp", "text": "10-Yard Fight (Japan)"},
            {"region": "us", "text": "10-Yard Fight"}
          ],
          "synopsis": [
            {"langue": "fr", "text": "Un jeu de football americain."},
            {"langue": "en", "text": "A simple arcade game based on American football."}
          ],
          "genres": [
            {"noms": [
              {"langue": "fr", "text": "Sport"},
              {"langue": "en", "text": "Sports"}
            ]}
          ],
          "joueurs": {"text": "1-2"},
          "developpeur": {"text": "Irem"},
          "editeur": {"text": "Nintendo"},
          "dates": [
            {"region": "jp", "text": "1985-10-01"},
            {"region": "us", "text": "1985-10-18"}
          ],
          "note": {"text": "16"},
          "medias": [
            {"type": "box-3D", "region": "us", "url": "https://example.com/box3d-us.png"},
            {"type": "box-2D", "region": "jp", "url": "https://example.com/box2d-jp.png"},
            {"type": "box-2D", "region": "us", "url": "https://example.com/box2d-us.png"}
          ]
        }
      }
    }
    """

    @Test func mapsAllFieldsPreferringUSRegionAndEnglishLanguage() throws {
        let envelope = try JSONDecoder().decode(ScreenScraperResponseEnvelope.self, from: Data(fullFixture.utf8))
        let info = try #require(ScreenScraperMapper.map(envelope))

        #expect(info.title == "10-Yard Fight")
        #expect(info.description == "A simple arcade game based on American football.")
        #expect(info.genre == "Sports")
        #expect(info.players == "1-2")
        #expect(info.developer == "Irem")
        #expect(info.publisher == "Nintendo")
        #expect(info.rating == 0.8) // 16 / 20
        #expect(info.coverArtURL == URL(string: "https://example.com/box2d-us.png"))

        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: try #require(info.releaseDate))
        #expect(components.year == 1985)
        #expect(components.month == 10)
        #expect(components.day == 18)
    }

    @Test func fallsBackToFirstEntryWhenPreferredRegionAndLanguageAreMissing() throws {
        let fixture = """
        {
          "response": {
            "jeu": {
              "noms": [{"region": "jp", "text": "Japan Only Title"}],
              "synopsis": [{"langue": "fr", "text": "Description francaise seulement."}]
            }
          }
        }
        """
        let envelope = try JSONDecoder().decode(ScreenScraperResponseEnvelope.self, from: Data(fixture.utf8))
        let info = try #require(ScreenScraperMapper.map(envelope))

        #expect(info.title == "Japan Only Title")
        #expect(info.description == "Description francaise seulement.")
    }

    @Test func missingJeuReturnsNil() throws {
        let fixture = #"{"response": {}}"#
        let envelope = try JSONDecoder().decode(ScreenScraperResponseEnvelope.self, from: Data(fixture.utf8))
        #expect(ScreenScraperMapper.map(envelope) == nil)
    }

    @Test func bareYearReleaseDateParses() throws {
        let fixture = """
        {"response": {"jeu": {"dates": [{"region": "us", "text": "1985"}]}}}
        """
        let envelope = try JSONDecoder().decode(ScreenScraperResponseEnvelope.self, from: Data(fixture.utf8))
        let info = try #require(ScreenScraperMapper.map(envelope))
        let year = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: try #require(info.releaseDate)).year
        #expect(year == 1985)
    }
}
