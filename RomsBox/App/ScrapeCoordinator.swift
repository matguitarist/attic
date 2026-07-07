import Foundation
import Observation
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxScraping

/// Fetches missing metadata/art for a single game from either ScreenScraper
/// or TheGamesDB and merges it in. Lives in the app layer (like
/// `ScanCoordinator`) since it touches the SwiftData `Game` model directly,
/// keeping `RomsBoxScraping` itself persistence-ignorant and independently
/// testable.
@Observable
@MainActor
final class ScrapeCoordinator {
    enum State: Equatable {
        case idle
        case scraping
        case failed(String)
    }

    private(set) var state: State = .idle

    private let screenScraperClient: ScreenScraperClientProtocol
    private let theGamesDBClient: TheGamesDBClientProtocol
    private let mediaCacheDirectory: URL

    init(
        screenScraperClient: ScreenScraperClientProtocol = ScreenScraperClient(),
        theGamesDBClient: TheGamesDBClientProtocol = TheGamesDBClient(),
        mediaCacheDirectory: URL = ScrapeCoordinator.defaultMediaCacheDirectory
    ) {
        self.screenScraperClient = screenScraperClient
        self.theGamesDBClient = theGamesDBClient
        self.mediaCacheDirectory = mediaCacheDirectory
    }

    static var defaultMediaCacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appending(path: "RomsBox/ScrapedMedia", directoryHint: .isDirectory)
    }

    /// Fills in only the fields currently missing on `game`, unless
    /// `force` is set — a rescan of a locally-curated gamelist.xml
    /// shouldn't silently get overwritten by a scrape, and re-scraping
    /// the same game repeatedly shouldn't keep re-downloading art it
    /// already has.
    func scrapeUsingScreenScraper(game: Game, credentials: ScreenScraperCredentials, force: Bool = false) async {
        guard let systemeID = ScreenScraperSystemID.systemeID(for: CanonicalSystemID(game.systemCanonicalID)) else {
            state = .failed("ScreenScraper doesn't support this system yet.")
            return
        }

        state = .scraping
        let romURL = game.romAbsoluteURL
        let romSizeBytes = (try? FileManager.default.attributesOfItem(atPath: romURL.path))?[.size] as? Int

        do {
            let info = try await screenScraperClient.fetchGameInfo(
                romFilename: romURL.lastPathComponent,
                romSizeBytes: romSizeBytes,
                systemeID: systemeID,
                credentials: credentials
            )
            try await apply(info, to: game, force: force)
            state = .idle
        } catch let error as ScreenScraperError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func scrapeUsingTheGamesDB(game: Game, credentials: TheGamesDBCredentials, force: Bool = false) async {
        guard let platformID = TheGamesDBSystemID.platformID(for: CanonicalSystemID(game.systemCanonicalID)) else {
            state = .failed("TheGamesDB doesn't support this system yet.")
            return
        }

        state = .scraping
        let romURL = game.romAbsoluteURL

        do {
            let info = try await theGamesDBClient.fetchGameInfo(
                romFilename: romURL.lastPathComponent,
                platformID: platformID,
                credentials: credentials
            )
            try await apply(info, to: game, force: force)
            state = .idle
        } catch let error as TheGamesDBError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func apply(_ info: ScrapedGameInfo, to game: Game, force: Bool) async throws {
        if force || game.gameDescription == nil { game.gameDescription = info.description ?? game.gameDescription }
        if force || game.developer == nil { game.developer = info.developer ?? game.developer }
        if force || game.publisher == nil { game.publisher = info.publisher ?? game.publisher }
        if force || game.genre == nil { game.genre = info.genre ?? game.genre }
        if force || game.players == nil { game.players = info.players ?? game.players }
        if force || game.releaseDate == nil { game.releaseDate = info.releaseDate ?? game.releaseDate }
        if force || game.rating == nil { game.rating = info.rating ?? game.rating }

        if (force || game.coverArtPath == nil), let remoteURL = info.coverArtURL {
            if let localURL = try? await downloadCoverArt(from: remoteURL, systemID: game.systemCanonicalID, romFilename: game.romAbsoluteURL.lastPathComponent) {
                game.coverArtPath = localURL.path
            }
        }

        try? game.modelContext?.save()
    }

    private func downloadCoverArt(from remoteURL: URL, systemID: String, romFilename: String) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        let systemDirectory = mediaCacheDirectory.appending(path: systemID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: systemDirectory, withIntermediateDirectories: true)

        let baseName = (romFilename as NSString).deletingPathExtension
        let ext = remoteURL.pathExtension.isEmpty ? "png" : remoteURL.pathExtension
        let destination = systemDirectory.appending(path: "\(baseName).\(ext)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func message(for error: ScreenScraperError) -> String {
        switch error {
        case .notConfigured:
            "ScreenScraper isn't configured yet — add your devID/devPassword in Settings."
        case .noMatch:
            "No match found on ScreenScraper for this ROM."
        case .credentialsRejectedOrQuotaExceeded(let detail):
            "ScreenScraper rejected the request (bad credentials or quota exceeded): \(detail)"
        case .network(let detail):
            "Network error: \(detail)"
        case .malformedResponse(let detail):
            "Unexpected response from ScreenScraper: \(detail)"
        }
    }

    private static func message(for error: TheGamesDBError) -> String {
        switch error {
        case .notConfigured:
            "TheGamesDB isn't configured yet — add your API key in Settings."
        case .noMatch:
            "No match found on TheGamesDB for this ROM."
        case .credentialsRejectedOrQuotaExceeded(let detail):
            "TheGamesDB rejected the request (bad API key or quota exceeded): \(detail)"
        case .network(let detail):
            "Network error: \(detail)"
        case .malformedResponse(let detail):
            "Unexpected response from TheGamesDB: \(detail)"
        }
    }
}
