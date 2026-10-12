import Foundation
import Testing
@testable import AtticScraping

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
        }
      }
    }
    """

    @Test func mapsAllFieldsAndPrefersFrontBoxart() throws {
        let envelope = try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fullFixture.utf8))
        let game = try #require(envelope.data?.games?.first)
        let names = TheGamesDBNames(genres: [7: "Sports"], developers: [55: "Irem"], publishers: [3: "Nintendo"])
        let info = TheGamesDBMapper.map(game, include: envelope.include, names: names)

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
        let info = TheGamesDBMapper.map(try #require(envelope.data?.games?.first), include: envelope.include, names: nil)
        #expect(info.coverArtURL == URL(string: "https://cdn.thegamesdb.net/images/original/back.jpg"))
    }

    @Test func noGamesHasNoBestMatch() {
        #expect(TheGamesDBMapper.bestMatch(in: [], for: "Anything") == nil)
    }

    @Test func bestMatchPrefersExactThenPrefixThenFirst() throws {
        let fixture = #"{"data": {"games": [{"id": 1, "game_title": "Super Metroid"}, {"id": 2, "game_title": "Metroid II: Return of Samus"}, {"id": 3, "game_title": "Metroid"}]}}"#
        let games = try #require(try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fixture.utf8)).data?.games)
        #expect(TheGamesDBMapper.bestMatch(in: games, for: "Metroid")?.id == 3)
        #expect(TheGamesDBMapper.bestMatch(in: games, for: "metroid ii")?.id == 2)
        #expect(TheGamesDBMapper.bestMatch(in: games, for: "Samus")?.id == 1)
    }

    @Test func bestMatchUsesAlternateTitles() throws {
        let fixture = #"{"data": {"games": [{"id": 1, "game_title": "Other"}, {"id": 2, "game_title": "Rockman", "alternates": ["Mega Man"]}]}}"#
        let games = try #require(try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fixture.utf8)).data?.games)
        #expect(TheGamesDBMapper.bestMatch(in: games, for: "Mega Man")?.id == 2)
    }

    @Test func missingNamesLeaveGenreDeveloperPublisherNil() throws {
        let fixture = #"{"data": {"games": [{"id": 5, "game_title": "Bare", "genres": [1]}]}}"#
        let envelope = try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: Data(fixture.utf8))
        let info = TheGamesDBMapper.map(try #require(envelope.data?.games?.first), include: envelope.include, names: nil)
        #expect(info.title == "Bare")
        #expect(info.genre == nil)
        #expect(info.developer == nil)
        #expect(info.publisher == nil)
        #expect(info.coverArtURL == nil)
    }
}
