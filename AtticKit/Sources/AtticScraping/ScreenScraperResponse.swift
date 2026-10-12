import Foundation

/// Mirrors ScreenScraper API v2's `jeuInfos.php` JSON shape closely enough
/// to decode it, without modeling fields Attic doesn't use. ScreenScraper
/// nests region/language-specific values as arrays-of-objects rather than
/// single localized strings (e.g. a game can have a `noms` entry per
/// region), so every text field here stays an array for `ScreenScraperMapper`
/// to pick a best match from.
///
/// Field names and nesting are based on publicly documented API usage in
/// existing open-source ScreenScraper clients (no official machine-readable
/// schema is published) — verify against a real response once real
/// devID/devPassword credentials are available, since ScreenScraper's API
/// has no versioned contract guarantee.
struct ScreenScraperResponseEnvelope: Decodable {
    let response: ScreenScraperResponseBody?
}

struct ScreenScraperResponseBody: Decodable {
    let jeu: ScreenScraperJeu?
}

struct ScreenScraperJeu: Decodable {
    let noms: [ScreenScraperRegionalText]?
    let synopsis: [ScreenScraperLocalizedText]?
    let genres: [ScreenScraperGenre]?
    let joueurs: ScreenScraperText?
    let developpeur: ScreenScraperText?
    let editeur: ScreenScraperText?
    let dates: [ScreenScraperRegionalText]?
    let note: ScreenScraperText?
    let medias: [ScreenScraperMedia]?
}

struct ScreenScraperGenre: Decodable {
    let noms: [ScreenScraperLocalizedText]?
}

struct ScreenScraperRegionalText: Decodable {
    let region: String?
    let text: String
}

struct ScreenScraperLocalizedText: Decodable {
    let langue: String?
    let text: String
}

struct ScreenScraperText: Decodable {
    let text: String
}

struct ScreenScraperMedia: Decodable {
    let type: String
    let region: String?
    let url: String
}
