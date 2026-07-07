import Foundation

/// Abstracted so `ScrapeCoordinator` (app layer) and tests can substitute a
/// fake implementation instead of hitting the real network.
public protocol ScreenScraperClientProtocol: Sendable {
    func fetchGameInfo(
        romFilename: String,
        romSizeBytes: Int?,
        systemeID: Int,
        credentials: ScreenScraperCredentials
    ) async throws -> ScrapedGameInfo
}

/// Matches a ROM by filename (+ optional file size) rather than by
/// CRC/MD5/SHA1 — those need reading each ROM's full contents to hash,
/// which would be slow across a library of hundreds of files. Filename
/// matching is the same fallback strategy ScreenScraper's own API and other
/// scraper clients support, and works well against No-Intro/Redump-style
/// filenames already common in Batocera/ES-DE libraries.
public struct ScreenScraperClient: ScreenScraperClientProtocol {
    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://www.screenscraper.fr/api2/jeuInfos.php")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchGameInfo(
        romFilename: String,
        romSizeBytes: Int?,
        systemeID: Int,
        credentials: ScreenScraperCredentials
    ) async throws -> ScrapedGameInfo {
        guard credentials.isConfigured else { throw ScreenScraperError.notConfigured }
        guard let url = requestURL(romFilename: romFilename, romSizeBytes: romSizeBytes, systemeID: systemeID, credentials: credentials) else {
            throw ScreenScraperError.malformedResponse("could not build request URL")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw ScreenScraperError.network(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ScreenScraperError.network("HTTP \(httpResponse.statusCode)")
        }

        if let bodyText = String(data: data, encoding: .utf8), Self.looksLikeErrorText(bodyText) {
            throw ScreenScraperError.credentialsRejectedOrQuotaExceeded(bodyText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let envelope: ScreenScraperResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ScreenScraperResponseEnvelope.self, from: data)
        } catch {
            throw ScreenScraperError.malformedResponse(error.localizedDescription)
        }

        guard let info = ScreenScraperMapper.map(envelope) else {
            throw ScreenScraperError.noMatch
        }
        return info
    }

    private func requestURL(romFilename: String, romSizeBytes: Int?, systemeID: Int, credentials: ScreenScraperCredentials) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }

        var items: [URLQueryItem] = [
            URLQueryItem(name: "devid", value: credentials.devID),
            URLQueryItem(name: "devpassword", value: credentials.devPassword),
            URLQueryItem(name: "softname", value: credentials.softwareName),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "systemeid", value: String(systemeID)),
            URLQueryItem(name: "romnom", value: romFilename)
        ]
        if let userID = credentials.userID, !userID.isEmpty {
            items.append(URLQueryItem(name: "ssid", value: userID))
        }
        if let userPassword = credentials.userPassword, !userPassword.isEmpty {
            items.append(URLQueryItem(name: "sspassword", value: userPassword))
        }
        if let romSizeBytes {
            items.append(URLQueryItem(name: "romtaille", value: String(romSizeBytes)))
        }
        components.queryItems = items
        return components.url
    }

    /// ScreenScraper returns plain text (not JSON, not a distinguishing
    /// HTTP status) for credential/quota failures rather than a documented
    /// machine-readable error, so this is a heuristic rather than a strict
    /// parse.
    private static func looksLikeErrorText(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{") else { return false }
        let lowered = trimmed.lowercased()
        return lowered.contains("erreur") || lowered.contains("developpeur") || lowered.contains("veuillez")
    }
}
