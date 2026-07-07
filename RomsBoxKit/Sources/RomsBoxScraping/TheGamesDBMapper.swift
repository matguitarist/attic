import Foundation

enum TheGamesDBMapper {
    /// Front box art is preferred; any other side is used as a fallback
    /// rather than showing nothing.
    private static let sidePreference = ["front"]

    static func map(_ envelope: TheGamesDBResponseEnvelope) -> ScrapedGameInfo? {
        guard let game = envelope.data?.games?.first else { return nil }

        return ScrapedGameInfo(
            title: game.gameTitle,
            description: game.overview,
            genre: firstName(ids: game.genres, in: envelope.include?.genre),
            players: game.players.map(String.init),
            developer: firstName(ids: game.developers, in: envelope.include?.developer),
            publisher: firstName(ids: game.publishers, in: envelope.include?.publisher),
            releaseDate: game.releaseDate.flatMap(parseDate),
            rating: nil, // TheGamesDB doesn't provide a numeric rating.
            coverArtURL: coverArtURL(forGameID: game.id, include: envelope.include?.boxart)
        )
    }

    private static func firstName(ids: [Int]?, in lookup: TheGamesDBNameLookup?) -> String? {
        guard let firstID = ids?.first, let lookup else { return nil }
        return lookup.data[String(firstID)]?.name
    }

    private static func coverArtURL(forGameID gameID: Int, include: TheGamesDBBoxArtInclude?) -> URL? {
        guard let include, let entries = include.data[String(gameID)] else { return nil }
        let boxartEntries = entries.filter { $0.type == "boxart" }
        for side in sidePreference {
            if let match = boxartEntries.first(where: { $0.side == side }) {
                return URL(string: include.baseURL.original + match.filename)
            }
        }
        guard let fallback = boxartEntries.first else { return nil }
        return URL(string: include.baseURL.original + fallback.filename)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }
}
