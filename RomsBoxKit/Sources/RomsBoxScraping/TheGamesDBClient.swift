import Foundation
import RomsBoxModels

/// Abstracted so `ScrapeCoordinator` and tests can substitute a fake
/// implementation instead of hitting the real network.
public protocol TheGamesDBClientProtocol: Sendable {
    /// `title` is the game's title as the library shows it (already cleaned
    /// of release tags, and resolved from arcade DATs for romsets).
    /// `wantsScreenshot` costs one more request (TheGamesDB's search
    /// results carry box art only), so callers ask only when they need one.
    func fetchGameInfo(
        title: String,
        platformID: Int,
        credentials: TheGamesDBCredentials,
        wantsScreenshot: Bool
    ) async throws -> ScrapedGameInfo
}

/// Matches by searching the game's title restricted to the given
/// platform — TheGamesDB's search is name-based, not filename/CRC-based
/// like ScreenScraper's, so results are inherently a bit fuzzier; the
/// closest title among the results wins. Genre, developer and publisher
/// ids are turned into names through `TheGamesDBNameCache`.
public struct TheGamesDBClient: TheGamesDBClientProtocol {
    private let session: URLSession
    private let apiRoot: URL
    private let nameCache: TheGamesDBNameCache

    /// - Parameter namesCacheURL: where genre/developer/publisher names are
    ///   kept between launches; `nil` keeps them in memory only.
    public init(
        session: URLSession = .shared,
        apiRoot: URL = URL(string: "https://api.thegamesdb.net/v1")!,
        namesCacheURL: URL? = nil
    ) {
        self.session = session
        self.apiRoot = apiRoot
        self.nameCache = TheGamesDBNameCache(fileURL: namesCacheURL)
    }

    public func fetchGameInfo(
        title: String,
        platformID: Int,
        credentials: TheGamesDBCredentials,
        wantsScreenshot: Bool = false
    ) async throws -> ScrapedGameInfo {
        guard credentials.isConfigured else { throw TheGamesDBError.notConfigured }
        let searchName = Self.searchName(fromTitle: title)
        guard let url = requestURL(searchName: searchName, platformID: platformID, credentials: credentials) else {
            throw TheGamesDBError.malformedResponse("could not build request URL")
        }

        let envelope: TheGamesDBResponseEnvelope = try await get(url)
        guard let game = TheGamesDBMapper.bestMatch(in: envelope.data?.games ?? [], for: searchName) else {
            throw TheGamesDBError.noMatch
        }
        let names = await nameCache.names(for: game) { [self] in
            try await fetchNames(credentials: credentials)
        }
        var info = TheGamesDBMapper.map(game, include: envelope.include, names: names)
        if wantsScreenshot {
            // Like the names, a nice-to-have: the scrape stands without it.
            info.screenshotURL = try? await screenshotURL(forGameID: game.id, credentials: credentials)
        }
        return info
    }

    private func screenshotURL(forGameID gameID: Int, credentials: TheGamesDBCredentials) async throws -> URL? {
        guard var components = URLComponents(url: apiRoot.appending(path: "Games/Images"), resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "apikey", value: credentials.apiKey),
            URLQueryItem(name: "games_id", value: String(gameID)),
            URLQueryItem(name: "filter[type]", value: "screenshot,titlescreen")
        ]
        guard let url = components.url else { return nil }
        let envelope: TheGamesDBImagesEnvelope = try await get(url)
        return TheGamesDBMapper.screenshotURL(forGameID: gameID, in: envelope)
    }

    private func fetchNames(credentials: TheGamesDBCredentials) async throws -> TheGamesDBNames {
        async let genres = nameList("Genres", credentials: credentials)
        async let developers = nameList("Developers", credentials: credentials)
        async let publishers = nameList("Publishers", credentials: credentials)
        return try await TheGamesDBNames(genres: genres, developers: developers, publishers: publishers)
    }

    private func nameList(_ endpoint: String, credentials: TheGamesDBCredentials) async throws -> [Int: String] {
        guard var components = URLComponents(url: apiRoot.appending(path: endpoint), resolvingAgainstBaseURL: false) else {
            throw TheGamesDBError.malformedResponse("could not build request URL")
        }
        components.queryItems = [URLQueryItem(name: "apikey", value: credentials.apiKey)]
        guard let url = components.url else { throw TheGamesDBError.malformedResponse("could not build request URL") }
        let envelope: TheGamesDBNameListEnvelope = try await get(url)
        return envelope.names
    }

    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TheGamesDBError.network(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                throw TheGamesDBError.credentialsRejectedOrQuotaExceeded(body)
            }
            if !(200..<300).contains(httpResponse.statusCode) {
                throw TheGamesDBError.network("HTTP \(httpResponse.statusCode)")
            }
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TheGamesDBError.malformedResponse(error.localizedDescription)
        }
    }

    private func requestURL(searchName: String, platformID: Int, credentials: TheGamesDBCredentials) -> URL? {
        guard var components = URLComponents(url: apiRoot.appending(path: "Games/ByGameName"), resolvingAgainstBaseURL: false) else { return nil }

        // Per the API spec (api.thegamesdb.net/spec.yaml): `include` takes
        // only `boxart` and `platform`; developers come back by default.
        components.queryItems = [
            URLQueryItem(name: "apikey", value: credentials.apiKey),
            URLQueryItem(name: "name", value: searchName),
            URLQueryItem(name: "filter[platform]", value: String(platformID)),
            URLQueryItem(name: "fields", value: "players,publishers,genres,overview,alternates"),
            URLQueryItem(name: "include", value: "boxart")
        ]
        return components.url
    }

    /// TheGamesDB matches plain title text, so drop anything a library
    /// title can still carry that it wouldn't know: release tags left in a
    /// hand-typed title, and the " / " that joins dual titles ("3 Count
    /// Bout / Fire Suplex" searches as "3 Count Bout").
    static func searchName(fromTitle title: String) -> String {
        let firstTitle = title.components(separatedBy: " / ").first ?? title
        let cleaned = ROMFilenameTitleCleaner.strippingTags(from: firstTitle)
        return cleaned.isEmpty ? title : cleaned
    }
}
