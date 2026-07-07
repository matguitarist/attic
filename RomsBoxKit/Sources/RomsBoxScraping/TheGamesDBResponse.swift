import Foundation

/// Mirrors TheGamesDB API v1's `Games/ByGameName` JSON shape closely enough
/// to decode it. Unlike ScreenScraper, genres/developers/publishers come
/// back as bare numeric ID arrays — resolved via the `include` object
/// (requested with `include=genres,developers,publishers,boxart`), which
/// embeds an id-to-name lookup table directly in the same response rather
/// than needing a separate request or a locally maintained static mapping.
///
/// Field names/nesting are based on publicly documented usage in existing
/// open-source TheGamesDB clients (no official machine-readable schema is
/// published) — verify against a real response once a real API key is
/// available, since there's no versioned contract guarantee.
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

    enum CodingKeys: String, CodingKey {
        case id
        case gameTitle = "game_title"
        case releaseDate = "release_date"
        case overview
        case players
        case genres
        case developers
        case publishers
    }
}

struct TheGamesDBInclude: Decodable {
    let boxart: TheGamesDBBoxArtInclude?
    let genre: TheGamesDBNameLookup?
    let developer: TheGamesDBNameLookup?
    let publisher: TheGamesDBNameLookup?
}

struct TheGamesDBNameLookup: Decodable {
    let data: [String: TheGamesDBNamedEntry]
}

struct TheGamesDBNamedEntry: Decodable {
    let name: String
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
