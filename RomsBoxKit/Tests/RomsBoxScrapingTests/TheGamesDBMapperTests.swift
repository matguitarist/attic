import Foundation
import Testing
@testable import RomsBoxScraping

@Suite struct TheGamesDBMapperTests {
    private let fullFixture = """
    {
      "data": {
        "games": [
          {
            "id": 1001,
            "game_title": "10-Yard Fight",
            "release_date": "1985-10-18",
            "overview": "A simple arcade game based on American football.",
            "players": 2,
            "genres": [7],
            "developers": [55],
            "publishers": [3]
          }
        ]
      },
      "include": {
        "boxart": {
          "base_url": {"original": "https://cdn.thegamesdb.net/images/original/"},
          "data": {
            "1001": [
              {"type": "boxart", "side": "back", "filename": "boxart/back/1001-1.jpg"},
              {"type": "boxart", "side": "front", "filename": "boxart/front/1001-1.jpg"},
              {"type": "fanart", "side": null, "filename": "fanart/1001-1.jpg"}
            ]
          }
        },
        "genre": {"data": {"7": {"name": "Sports"}}},
        "developer": {"data": {"55": {"name": "Irem"}}},
        "publisher": {"data": {"3": {"name": "Nintendo"}}}
      }
    }
    """

    @Test func mapsAllFieldsAndPrefersFrontBoxart() throws {
        let envelope = try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fullFixture.utf8))
        let info = try #require(TheGamesDBMapper.map(envelope))

        #expect(info.title == "10-Yard Fight")
        #expect(info.description == "A simple arcade game based on American football.")
        #expect(info.genre == "Sports")
        #expect(info.players == "2")
        #expect(info.developer == "Irem")
        #expect(info.publisher == "Nintendo")
        #expect(info.rating == nil)
        #expect(info.coverArtURL == URL(string: "https://cdn.thegamesdb.net/images/original/boxart/front/1001-1.jpg"))

        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: try #require(info.releaseDate))
        #expect(components.year == 1985)
        #expect(components.month == 10)
        #expect(components.day == 18)
    }

    @Test func fallsBackToAnyBoxartSideWhenFrontIsMissing() throws {
        let fixture = """
        {
          "data": {"games": [{"id": 2, "game_title": "Test"}]},
          "include": {
            "boxart": {
              "base_url": {"original": "https://cdn.thegamesdb.net/images/original/"},
              "data": {"2": [{"type": "boxart", "side": "back", "filename": "back.jpg"}]}
            }
          }
        }
        """
        let envelope = try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fixture.utf8))
        let info = try #require(TheGamesDBMapper.map(envelope))
        #expect(info.coverArtURL == URL(string: "https://cdn.thegamesdb.net/images/original/back.jpg"))
    }

    @Test func noGamesReturnsNil() throws {
        let fixture = #"{"data": {"games": []}}"#
        let envelope = try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fixture.utf8))
        #expect(TheGamesDBMapper.map(envelope) == nil)
    }

    @Test func missingIncludeLeavesGenreDeveloperPublisherNil() throws {
        let fixture = #"{"data": {"games": [{"id": 5, "game_title": "Bare"}]}}"#
        let envelope = try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fixture.utf8))
        let info = try #require(TheGamesDBMapper.map(envelope))
        #expect(info.title == "Bare")
        #expect(info.genre == nil)
        #expect(info.developer == nil)
        #expect(info.publisher == nil)
        #expect(info.coverArtURL == nil)
    }
}
