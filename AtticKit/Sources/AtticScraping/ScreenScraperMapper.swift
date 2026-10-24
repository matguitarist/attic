import Foundation

/// Picks one best-match value out of ScreenScraper's region/language arrays
/// and flattens the response into `ScrapedGameInfo`.
enum ScreenScraperMapper {
    /// Preference order for region-tagged fields (names, release dates).
    private static let regionPreference = ["us", "wor", "eu", "ss", "jp"]
    /// Preference order for language-tagged fields (synopsis, genre names).
    private static let languagePreference = ["en", "us"]
    /// Preference order for cover art media types — ScreenScraper's
    /// "mixrsdb"/"box-2D" families are the closest match to a single
    /// front-cover image; box-3D is a rendered 3D box, used as a fallback.
    private static let coverMediaTypePreference = ["box-2D", "box-2D-side", "mixrsdb", "box-3D"]
    /// "ss" is an in-game screenshot, "sstitle" the title screen.
    private static let screenshotMediaTypePreference = ["ss", "sstitle"]
    /// "video-normalized" is the smaller, re-encoded cut.
    private static let videoMediaTypePreference = ["video-normalized", "video"]
    /// The logo: "wheel-hd" is the larger cut; the carbon and steel ones
    /// are the logo on a backing plate.
    private static let logoMediaTypePreference = ["wheel-hd", "wheel"]

    static func map(_ envelope: ScreenScraperResponseEnvelope) -> ScrapedGameInfo? {
        guard let jeu = envelope.response?.jeu else { return nil }

        return ScrapedGameInfo(
            title: bestRegional(jeu.noms)?.text,
            description: bestLocalized(jeu.synopsis)?.text,
            genre: jeu.genres?.first.flatMap { bestLocalized($0.noms)?.text },
            players: jeu.joueurs?.text,
            developer: jeu.developpeur?.text,
            publisher: jeu.editeur?.text,
            releaseDate: bestRegional(jeu.dates).flatMap { parseDate($0.text) },
            rating: (jeu.note?.text).flatMap { Double($0) }.map { $0 / 20.0 },
            coverArtURL: bestMedia(jeu.medias, types: coverMediaTypePreference),
            screenshotURL: bestMedia(jeu.medias, types: screenshotMediaTypePreference),
            videoURL: bestMedia(jeu.medias, types: videoMediaTypePreference),
            logoURL: bestMedia(jeu.medias, types: logoMediaTypePreference),
            fanartURL: bestMedia(jeu.medias, types: ["fanart"]),
            box3DURL: bestMedia(jeu.medias, types: ["box-3D"]),
            physicalMediaURL: bestMedia(jeu.medias, types: ["support-2D"])
        )
    }

    private static func bestRegional(_ items: [ScreenScraperRegionalText]?) -> ScreenScraperRegionalText? {
        guard let items, !items.isEmpty else { return nil }
        for region in regionPreference {
            if let match = items.first(where: { $0.region == region }) { return match }
        }
        return items.first
    }

    private static func bestLocalized(_ items: [ScreenScraperLocalizedText]?) -> ScreenScraperLocalizedText? {
        guard let items, !items.isEmpty else { return nil }
        for language in languagePreference {
            if let match = items.first(where: { $0.langue == language }) { return match }
        }
        return items.first
    }

    private static func bestMedia(_ media: [ScreenScraperMedia]?, types: [String]) -> URL? {
        guard let media, !media.isEmpty else { return nil }
        for type in types {
            let candidates = media.filter { $0.type == type }
            if let regional = bestRegionalMedia(candidates) { return URL(string: regional.url) }
        }
        return nil
    }

    private static func bestRegionalMedia(_ items: [ScreenScraperMedia]) -> ScreenScraperMedia? {
        guard !items.isEmpty else { return nil }
        for region in regionPreference {
            if let match = items.first(where: { $0.region == region }) { return match }
        }
        return items.first
    }

    /// ScreenScraper release dates are typically `YYYY-MM-DD`, sometimes a
    /// bare `YYYY`.
    private static func parseDate(_ raw: String) -> Date? {
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "yyyy-MM-dd"
        fullFormatter.locale = Locale(identifier: "en_US_POSIX")
        fullFormatter.timeZone = TimeZone(identifier: "UTC")
        if let date = fullFormatter.date(from: raw) { return date }

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        yearFormatter.locale = Locale(identifier: "en_US_POSIX")
        yearFormatter.timeZone = TimeZone(identifier: "UTC")
        return yearFormatter.date(from: raw)
    }
}
