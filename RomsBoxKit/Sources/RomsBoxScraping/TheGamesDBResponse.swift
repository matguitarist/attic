import Foundation

/// Mirrors TheGamesDB API v1's `Games/ByGameName` JSON shape, as described
/// by its OpenAPI spec (https://api.thegamesdb.net/spec.yaml). Unlike
/// ScreenScraper, genres/developers/publishers come back as bare numeric
/// id arrays; `TheGamesDBNames` resolves them.
struct TheGamesDBResponseEnvelope: Decodable {
    let data: TheGamesDBData?
    let include: TheGamesDBInclude?
}

struct TheGamesDBData: Decodable {
    let games: [TheGamesDBGame]?
}

struct TheGamesDBGame: Decodable {
    let id: Int
    let gameTitle: String?
    let releaseDate: String?
    let overview: String?
    let players: Int?
    let genres: [Int]?
    let developers: [Int]?
    let publishers: [Int]?
    let alternates: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case gameTitle = "game_title"
        case releaseDate = "release_date"
        case overview
        case players
        case genres
        case developers
        case publishers
        case alternates
    }
}

struct TheGamesDBInclude: Decodable {
    let boxart: TheGamesDBBoxArtInclude?
}

struct TheGamesDBBoxArtInclude: Decodable {
    let baseURL: TheGamesDBBoxArtBaseURL
    let data: [String: [TheGamesDBBoxArtEntry]]

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case data
    }
}

struct TheGamesDBBoxArtBaseURL: Decodable {
    let original: String
}

struct TheGamesDBBoxArtEntry: Decodable {
    let type: String
    let side: String?
    let filename: String
}
