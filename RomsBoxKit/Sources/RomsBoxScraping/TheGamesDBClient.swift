import Foundation

/// Abstracted so `ScrapeCoordinator` and tests can substitute a fake
/// implementation instead of hitting the real network.
public protocol TheGamesDBClientProtocol: Sendable {
    func fetchGameInfo(
        romFilename: String,
        platformID: Int,
        credentials: TheGamesDBCredentials
    ) async throws -> ScrapedGameInfo
}

/// Matches by searching the ROM's filename (with its extension and common
/// release-group bracketed tags stripped) restricted to the given
/// platform — TheGamesDB's search is name-based, not filename/CRC-based
/// like ScreenScraper's, so results are inherently a bit fuzzier.
public struct TheGamesDBClient: TheGamesDBClientProtocol {
    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.thegamesdb.net/v1/Games/ByGameName")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchGameInfo(
        romFilename: String,
        platformID: Int,
        credentials: TheGamesDBCredentials
    ) async throws -> ScrapedGameInfo {
        guard credentials.isConfigured else { throw TheGamesDBError.notConfigured }
        guard let url = requestURL(romFilename: romFilename, platformID: platformID, credentials: credentials) else {
            throw TheGamesDBError.malformedResponse("could not build request URL")
        }

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

        let envelope: TheGamesDBResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(TheGamesDBResponseEnvelope.self, from: data)
        } catch {
            throw TheGamesDBError.malformedResponse(error.localizedDescription)
        }

        guard let info = TheGamesDBMapper.map(envelope) else {
            throw TheGamesDBError.noMatch
        }
        return info
    }

    private func requestURL(romFilename: String, platformID: Int, credentials: TheGamesDBCredentials) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "apikey", value: credentials.apiKey),
            URLQueryItem(name: "name", value: Self.searchName(fromROMFilename: romFilename)),
            URLQueryItem(name: "filter[platform]", value: String(platformID)),
            URLQueryItem(name: "fields", value: "players,publishers,genres,overview,release_date"),
            URLQueryItem(name: "include", value: "genres,developers,publishers,boxart")
        ]
        return components.url
    }

    /// Strips the file extension and any parenthesized/bracketed release
    /// tags (`(USA)`, `[!]`, `(Europe) (En,Fr,De)`, …) common in
    /// No-Intro/Redump-style filenames, since TheGamesDB matches by plain
    /// title text rather than filename conventions.
    static func searchName(fromROMFilename filename: String) -> String {
        let nameNoExt = (filename as NSString).deletingPathExtension
        let withoutTags = nameNoExt.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        return withoutTags.trimmingCharacters(in: .whitespaces)
    }
}
