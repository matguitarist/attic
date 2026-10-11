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

    enum BatchState: Equatable {
        case idle
        case running(completed: Int, total: Int)
        case finished(scraped: Int, alreadyPresent: Int, failed: Int)
    }

    enum ScraperSource {
        case screenScraper(ScreenScraperCredentials)
        case theGamesDB(TheGamesDBCredentials)
    }

    private(set) var state: State = .idle
    private(set) var batchState: BatchState = .idle
    private var batchTask: Task<Void, Never>?

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

    /// Scrapes every game in `games` that's missing a description (the same
    /// proxy the single-game path uses for "not yet scraped"), skipping
    /// ones that already have one so a huge library doesn't re-request data
    /// it already has. Runs sequentially with a small pause between
    /// requests — free-tier accounts on both sources have tight rate/thread
    /// limits, and hundreds of games hammered concurrently would just get
    /// rejected.
    func scrapeAllMissing(games: [Game], source: ScraperSource) {
        batchTask?.cancel()
        batchTask = Task { [weak self] in
            await self?.runBatch(games: games, source: source)
        }
    }

    func cancelBatch() {
        batchTask?.cancel()
        batchTask = nil
        batchState = .idle
    }

    private func runBatch(games: [Game], source: ScraperSource) async {
        let missing = games.filter { $0.gameDescription == nil }
        guard !missing.isEmpty else {
            batchState = .finished(scraped: 0, alreadyPresent: games.count, failed: 0)
            return
        }

        var scraped = 0
        var failed = 0
        for (index, game) in missing.enumerated() {
            if Task.isCancelled { return }
            batchState = .running(completed: index, total: missing.count)

            switch source {
            case .screenScraper(let credentials):
                await scrapeUsingScreenScraper(game: game, credentials: credentials)
            case .theGamesDB(let credentials):
                await scrapeUsingTheGamesDB(game: game, credentials: credentials)
            }
            if case .failed = state { failed += 1 } else { scraped += 1 }

            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        batchState = .finished(scraped: scraped, alreadyPresent: games.count - missing.count, failed: failed)
    }

    /// Scraped results are kept app-only, never written back into
    /// gamelist.xml — but still need protecting from a *future* rescan,
    /// which re-imports straight from gamelist.xml and would otherwise
    /// silently erase whatever a scrape just filled in. Setting the same
    /// `metadataManuallyEdited` flag GameDetailView's editable fields use
    /// covers both cases with one mechanism.
    private func apply(_ info: ScrapedGameInfo, to game: Game, force: Bool) async throws {
        var changedProtectedField = false
        if force || game.gameDescription == nil {
            if info.description != nil { game.gameDescription = info.description; changedProtectedField = true }
        }
        if force || game.developer == nil {
            if info.developer != nil { game.developer = info.developer; changedProtectedField = true }
        }
        if force || game.publisher == nil {
            if info.publisher != nil { game.publisher = info.publisher; changedProtectedField = true }
        }
        if force || game.genre == nil {
            if info.genre != nil { game.genre = info.genre; changedProtectedField = true }
        }
        if force || game.players == nil {
            if info.players != nil { game.players = info.players; changedProtectedField = true }
        }
        if force || game.releaseDate == nil { game.releaseDate = info.releaseDate ?? game.releaseDate }
        if force || game.rating == nil { game.rating = info.rating ?? game.rating }

        if (force || game.coverArtPath == nil), let remoteURL = info.coverArtURL {
            if let localURL = try? await downloadCoverArt(from: remoteURL, systemID: game.systemCanonicalID, romFilename: game.romAbsoluteURL.lastPathComponent) {
                game.coverArtPath = localURL.path
            }
        }

        if changedProtectedField {
            game.metadataManuallyEdited = true
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
        CoverArtThumbnailCache.shared.invalidate(destination)
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
