import Foundation

enum TheGamesDBMapper {
    /// Front box art is preferred; any other side is used as a fallback
    /// rather than showing nothing.
    private static let sidePreference = ["front"]

    static func map(_ game: TheGamesDBGame, include: TheGamesDBInclude?, names: TheGamesDBNames?) -> ScrapedGameInfo {
        ScrapedGameInfo(
            title: game.gameTitle,
            description: game.overview,
            genre: joinedNames(ids: game.genres, in: names?.genres),
            players: game.players.map(String.init),
            developer: joinedNames(ids: game.developers, in: names?.developers),
            publisher: joinedNames(ids: game.publishers, in: names?.publishers),
            releaseDate: game.releaseDate.flatMap(parseDate),
            rating: nil, // TheGamesDB's `rating` is an age rating ("E - Everyone"), not a score.
            coverArtURL: coverArtURL(forGameID: game.id, include: include?.boxart)
        )
    }

    /// The result whose title (or one of its alternate titles) matches the
    /// search best: an exact match, then one starting with it, else the
    /// search's own first result. Searching "Metroid" returns "Super
    /// Metroid" and "Metroid II" too, not always in the right order.
    static func bestMatch(in games: [TheGamesDBGame], for searchName: String) -> TheGamesDBGame? {
        let wanted = normalized(searchName)
        func titles(_ game: TheGamesDBGame) -> [String] {
            ([game.gameTitle].compactMap { $0 } + (game.alternates ?? [])).map(normalized)
        }
        return games.first { titles($0).contains(wanted) }
            ?? games.first { titles($0).contains { $0.hasPrefix(wanted) } }
            ?? games.first
    }

    private static func normalized(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// "Action, Platform" — every name the game lists, in its order.
    private static func joinedNames(ids: [Int]?, in lookup: [Int: String]?) -> String? {
        guard let ids, let lookup else { return nil }
        let names = ids.compactMap { lookup[$0] }
        return names.isEmpty ? nil : names.joined(separator: ", ")
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
