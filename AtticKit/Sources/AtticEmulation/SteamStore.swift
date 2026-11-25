import Foundation
import SteamKit

/// A Steam game's info and artwork from the Steam store, which needs no
/// account or key: the text from `appdetails`, and the library pictures
/// (portrait cover, hero, logo) from `IStoreBrowseService/GetItems`, whose
/// file names are content hashes for newer games, so they can't be guessed.
/// A game with no store page (delisted, or not sold here) still gets its
/// makers, date, genres, players and rating from the Steam client's app
/// info, as steamcmd.net serves it.
public struct SteamStoreInfo: Equatable, Sendable {
    public var description: String?
    public var developer: String?
    public var publisher: String?
    public var genre: String?
    public var releaseDate: Date?
    /// "1" for a single-player game, "1-2" when it has any multiplayer or
    /// co-op mode: Steam says which modes, not how many players.
    public var players: String?
    /// 0...1: Steam's user reviews (the share that are positive), else
    /// the Metacritic score.
    public var rating: Double?
    /// The library's portrait cover, its wide hero picture (fan art), its
    /// logo, and the first screenshot.
    public var coverURL: URL?
    public var heroURL: URL?
    public var logoURL: URL?
    public var screenshotURL: URL?
    /// The HLS playlist of its highlighted trailer (see `SteamTrailer`).
    public var trailerURL: URL?

    public init(description: String? = nil, developer: String? = nil, publisher: String? = nil, genre: String? = nil,
                releaseDate: Date? = nil, players: String? = nil, rating: Double? = nil, coverURL: URL? = nil, heroURL: URL? = nil, logoURL: URL? = nil, screenshotURL: URL? = nil,
                trailerURL: URL? = nil) {
        self.description = description
        self.developer = developer
        self.publisher = publisher
        self.genre = genre
        self.releaseDate = releaseDate
        self.players = players
        self.rating = rating
        self.coverURL = coverURL
        self.heroURL = heroURL
        self.logoURL = logoURL
        self.screenshotURL = screenshotURL
        self.trailerURL = trailerURL
    }
}

public enum SteamStore {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// Everything the store has on `appID`; what it doesn't have stays nil.
    public static func info(appID: String, fetch: Fetch) async -> SteamStoreInfo {
        var info = SteamStoreInfo()
        if let data = try? await fetch(SteamKit.SteamStore.detailsURL(appID: appID)) {
            info = details(from: data, appID: appID) ?? info
        }
        if let data = try? await fetch(SteamKit.SteamStore.assetsURL(appID: appID)) {
            let assets = SteamKit.SteamStore.assets(from: data)
            info.coverURL = assets.cover ?? info.coverURL
            info.heroURL = assets.hero
            info.logoURL = assets.logo
        }
        // The app info the Steam client reads: the library logo the store
        // doesn't always list (under a hashed name), the user reviews'
        // score, and the rest for a game with no store page.
        if let data = try? await fetch(appInfoURL(appID: appID)) {
            if info.logoURL == nil { info.logoURL = libraryLogo(fromAppInfo: data, appID: appID) }
            if let client = appInfo(from: data, appID: appID) {
                info.developer = info.developer ?? client.developer
                info.publisher = info.publisher ?? client.publisher
                info.genre = info.genre ?? client.genre
                info.releaseDate = info.releaseDate ?? client.releaseDate
                info.players = info.players ?? client.players
                info.rating = client.rating ?? info.rating
            }
        }
        return info
    }

    /// The Steam client's app info: makers, release date, genres and
    /// modes by Steam's numbers, and the user reviews' score.
    static func appInfo(from data: Data, appID: String) -> SteamStoreInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let common = ((root["data"] as? [String: Any])?[appID] as? [String: Any])?["common"] as? [String: Any] else { return nil }
        /// Its lists are objects keyed "0", "1"…, in order.
        func list(_ key: String) -> [Any] {
            guard let object = common[key] as? [String: Any] else { return [] }
            return object.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { object[$0] }
        }
        let associations = list("associations").compactMap { $0 as? [String: Any] }
        func names(_ type: String) -> String? {
            let found = associations.filter { $0["type"] as? String == type }.compactMap { $0["name"] as? String }
            return found.isEmpty ? nil : found.joined(separator: ", ")
        }
        let genres = list("genres").compactMap { ($0 as? String).flatMap(Int.init).flatMap { genreNames[$0] } }
        let categories = Set((common["category"] as? [String: Any])?.keys.compactMap { Int($0.replacing("category_", with: "")) } ?? [])
        let released = (common["original_release_date"] as? String ?? common["steam_release_date"] as? String)
            .flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
        let reviews = (common["review_percentage"] as? String).flatMap(Double.init)
        let metacritic = (common["metacritic_score"] as? String).flatMap(Double.init)
        return SteamStoreInfo(
            developer: names("developer"), publisher: names("publisher"),
            genre: genres.isEmpty ? nil : genres.joined(separator: ", "),
            releaseDate: released,
            players: players(categoryIDs: categories),
            rating: (reviews ?? metacritic).flatMap { $0 > 0 ? $0 / 100 : nil }
        )
    }

    /// Steam's genre numbers, as its store names them.
    static let genreNames: [Int: String] = [
        1: "Action", 2: "Strategy", 3: "RPG", 4: "Casual", 9: "Racing", 18: "Sports", 23: "Indie", 25: "Adventure",
        28: "Simulation", 29: "Massively Multiplayer", 37: "Free To Play", 70: "Early Access"
    ]

    /// Steam's multiplayer and co-op modes, by its category numbers:
    /// multi-player, co-op, PvP, split screen, online and LAN.
    static let multiplayerCategories: Set<Int> = [1, 9, 24, 27, 36, 37, 38, 39, 47, 48, 49]

    /// "1-2" when any mode is for several players, "1" for single-player
    /// only, nil when Steam lists neither.
    static func players(categoryIDs: Set<Int>) -> String? {
        if !categoryIDs.isDisjoint(with: multiplayerCategories) { return "1-2" }
        return categoryIDs.contains(2) ? "1" : nil
    }

    /// Older games' logo, at the classic address, for when nothing else
    /// has one (a miss just downloads nothing).
    public static func classicLogoURL(appID: String) -> URL {
        SteamKit.SteamStore.classicLogoURL(appID: appID)
    }

    /// The Steam client's app info, as steamcmd.net serves it.
    static func appInfoURL(appID: String) -> URL {
        URL(string: "https://api.steamcmd.net/v1/info/\(appID)")!
    }

    /// The English library logo in the app info, twice the size when
    /// there is one.
    static func libraryLogo(fromAppInfo data: Data, appID: String) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = (root["data"] as? [String: Any])?[appID] as? [String: Any],
              let assets = (app["common"] as? [String: Any])?["library_assets_full"] as? [String: Any],
              let logo = assets["library_logo"] as? [String: Any] else { return nil }
        let file = ((logo["image2x"] as? [String: Any])?["english"] ?? (logo["image"] as? [String: Any])?["english"]) as? String
        return file.flatMap { URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/\($0)") }
    }

    /// `appdetails`' answer, read by SteamKit: the short description as
    /// plain text, makers, genres, release date, and the wide header as a
    /// cover until a portrait one is found.
    static func details(from data: Data, appID: String) -> SteamStoreInfo? {
        guard let store = SteamKit.SteamStore.details(from: data, appID: appID) else { return nil }
        func joined(_ names: [String]) -> String? { names.isEmpty ? nil : names.joined(separator: ", ") }
        let description = store.shortDescription.map(plainText)
        return SteamStoreInfo(
            description: description?.isEmpty == false ? description : nil,
            developer: joined(store.developers),
            publisher: joined(store.publishers),
            genre: joined(store.genres),
            releaseDate: store.releaseDate,
            players: players(categoryIDs: store.categoryIDs),
            rating: store.metacriticScore.map { Double($0) / 100 },
            coverURL: store.headerImage,
            screenshotURL: store.screenshots.first,
            // The trailer the store page leads with, else the first.
            trailerURL: store.trailers.first
        )
    }

    /// Store text can hold HTML entities and the odd tag.
    private static func plainText(_ html: String) -> String {
        var text = html.replacing(/<[^>]+>/, with: "")
        for (entity, character) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
