import Foundation

/// Community artwork from SteamGridDB (steamgriddb.com), looked up by a
/// game's Steam app ID: portrait covers ("grids"), heroes and logos, for
/// what the Steam store doesn't have. Needs the user's free API key.
public enum SteamGridDB {
    public enum Art: String, Sendable, CaseIterable {
        case cover = "grids"
        case hero = "heroes"
        case logo = "logos"
    }

    public typealias Fetch = @Sendable (URLRequest) async throws -> Data

    /// The best-rated still picture of `art` for the game, if any.
    public static func url(of art: Art, appID: String, apiKey: String, fetch: Fetch) async -> URL? {
        var request = URLRequest(url: requestURL(art, appID: appID))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let data = try? await fetch(request) else { return nil }
        return firstURL(in: data)
    }

    static func requestURL(_ art: Art, appID: String) -> URL {
        var components = URLComponents(string: "https://www.steamgriddb.com/api/v2/\(art.rawValue)/steam/\(appID)")!
        var query = [URLQueryItem(name: "types", value: "static"), URLQueryItem(name: "nsfw", value: "false")]
        // Portrait covers, the size Steam's own library uses.
        if art == .cover { query.append(URLQueryItem(name: "dimensions", value: "600x900,342x482,660x930")) }
        components.queryItems = query
        return components.url!
    }

    /// The first picture of a `{ "success": true, "data": [ { "url": … } ] }`
    /// answer; SteamGridDB lists them best-rated first.
    static func firstURL(in data: Data) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["success"] as? Bool == true,
              let pictures = root["data"] as? [[String: Any]] else { return nil }
        return pictures.lazy.compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.first
    }
}
