import Foundation

/// A Steam game's info and artwork from the Steam store, which needs no
/// account or key: the text from `appdetails`, and the library pictures
/// (portrait cover, hero, logo) from `IStoreBrowseService/GetItems`, whose
/// file names are content hashes for newer games, so they can't be guessed.
public struct SteamStoreInfo: Equatable, Sendable {
    public var description: String?
    public var developer: String?
    public var publisher: String?
    public var genre: String?
    public var releaseDate: Date?
    /// The library's portrait cover, its wide hero picture (fan art), its
    /// logo, and the first screenshot.
    public var coverURL: URL?
    public var heroURL: URL?
    public var logoURL: URL?
    public var screenshotURL: URL?

    public init(description: String? = nil, developer: String? = nil, publisher: String? = nil, genre: String? = nil,
                releaseDate: Date? = nil, coverURL: URL? = nil, heroURL: URL? = nil, logoURL: URL? = nil, screenshotURL: URL? = nil) {
        self.description = description
        self.developer = developer
        self.publisher = publisher
        self.genre = genre
        self.releaseDate = releaseDate
        self.coverURL = coverURL
        self.heroURL = heroURL
        self.logoURL = logoURL
        self.screenshotURL = screenshotURL
    }
}

public enum SteamStore {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// Everything the store has on `appID`; what it doesn't have stays nil.
    public static func info(appID: String, fetch: Fetch) async -> SteamStoreInfo {
        var info = SteamStoreInfo()
        if let data = try? await fetch(detailsURL(appID: appID)) {
            info = details(from: data, appID: appID) ?? info
        }
        if let data = try? await fetch(assetsURL(appID: appID)) {
            let assets = assets(from: data)
            info.coverURL = assets.cover ?? info.coverURL
            info.heroURL = assets.hero
            info.logoURL = assets.logo
        }
        // The store doesn't list every game's logo; older games have one
        // at the classic address (a miss just downloads nothing).
        if info.logoURL == nil {
            info.logoURL = URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/logo.png")
        }
        return info
    }

    static func detailsURL(appID: String) -> URL {
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [URLQueryItem(name: "appids", value: appID), URLQueryItem(name: "l", value: "english")]
        return components.url!
    }

    static func assetsURL(appID: String) -> URL {
        let request = #"{"ids":[{"appid":\#(appID)}],"context":{"language":"english","country_code":"US"},"data_request":{"include_assets":true}}"#
        var components = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1")!
        components.queryItems = [URLQueryItem(name: "input_json", value: request)]
        return components.url!
    }

    /// `appdetails`' answer: the short description, makers, genres,
    /// release date, and the wide header as a cover until a portrait one
    /// is found.
    static func details(from data: Data, appID: String) -> SteamStoreInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[appID] as? [String: Any], entry["success"] as? Bool == true,
              let game = entry["data"] as? [String: Any] else { return nil }
        func joined(_ key: String) -> String? {
            (game[key] as? [String]).flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") }
        }
        let genres = (game["genres"] as? [[String: Any]])?.compactMap { $0["description"] as? String } ?? []
        let screenshot = (game["screenshots"] as? [[String: Any]])?.first?["path_full"] as? String
        let description = (game["short_description"] as? String).map(plainText)
        return SteamStoreInfo(
            description: description?.isEmpty == false ? description : nil,
            developer: joined("developers"),
            publisher: joined("publishers"),
            genre: genres.isEmpty ? nil : genres.joined(separator: ", "),
            releaseDate: ((game["release_date"] as? [String: Any])?["date"] as? String).flatMap(releaseDate),
            coverURL: (game["header_image"] as? String).flatMap(URL.init(string:)),
            screenshotURL: screenshot.flatMap(URL.init(string:))
        )
    }

    /// `GetItems`' asset file names, put into its URL format.
    static func assets(from data: Data) -> (cover: URL?, hero: URL?, logo: URL?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = ((root["response"] as? [String: Any])?["store_items"] as? [[String: Any]])?.first,
              let assets = item["assets"] as? [String: Any],
              let format = assets["asset_url_format"] as? String else { return (nil, nil, nil) }
        func url(_ keys: String...) -> URL? {
            for key in keys {
                guard let name = assets[key] as? String, !name.isEmpty else { continue }
                return URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/"
                    + format.replacingOccurrences(of: "${FILENAME}", with: name))
            }
            return nil
        }
        return (url("library_capsule_2x", "library_capsule"), url("library_hero_2x", "library_hero"), url("library_logo_2x", "library_logo"))
    }

    /// The store writes dates for its English page as "16 Jul, 2026" or
    /// "Jul 16, 2026"; just a year, or "Coming soon", give nothing.
    static func releaseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["d MMM, yyyy", "MMM d, yyyy", "d MMMM, yyyy", "MMMM d, yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
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
