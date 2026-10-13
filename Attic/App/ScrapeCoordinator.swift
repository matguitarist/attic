import Foundation
import AtticEmulation
import AtticLibraryScanning
import Observation
import AtticModels
import AtticPersistence
import AtticScraping

/// Fetches missing metadata/art for a single game from either ScreenScraper
/// or TheGamesDB and merges it in. Lives in the app layer (like
/// `ScanCoordinator`) since it touches the SwiftData `Game` model directly,
/// keeping `AtticScraping` itself persistence-ignorant and independently
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

        var name: String {
            switch self {
            case .screenScraper: "ScreenScraper"
            case .theGamesDB: "TheGamesDB"
            }
        }
    }

    /// A single game's scrape (from a menu), for the status bar: running,
    /// then what it changed. Batch scrapes report through `batchState`.
    enum Activity: Equatable {
        case scraping(title: String, source: String)
        case updated(title: String, fields: [String])
        case nothingNew(title: String)
        case failed(title: String, message: String)
    }

    private(set) var state: State = .idle
    private(set) var batchState: BatchState = .idle
    private(set) var activity: Activity?
    private var activityClearTask: Task<Void, Never>?
    private var batchTask: Task<Void, Never>?

    private let screenScraperClient: ScreenScraperClientProtocol
    private let theGamesDBClient: TheGamesDBClientProtocol

    init(
        screenScraperClient: ScreenScraperClientProtocol = ScreenScraperClient(),
        theGamesDBClient: TheGamesDBClientProtocol = TheGamesDBClient(namesCacheURL: ScrapeCoordinator.theGamesDBNamesCacheURL)
    ) {
        self.screenScraperClient = screenScraperClient
        self.theGamesDBClient = theGamesDBClient
    }

    static var theGamesDBNamesCacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appending(path: "Attic/TheGamesDBNames.json")
    }

    /// Scrapes one game, reporting progress and the outcome in the status
    /// bar. A success message clears itself after a few seconds; a failure
    /// stays until dismissed.
    func scrape(_ game: Game, from source: ScraperSource, force: Bool = false) async {
        activityClearTask?.cancel()
        let title = game.title
        activity = .scraping(title: title, source: source.name)
        let fields: [String]?
        switch source {
        case .screenScraper(let credentials):
            fields = await scrapeUsingScreenScraper(game: game, credentials: credentials, force: force)
        case .theGamesDB(let credentials):
            fields = await scrapeUsingTheGamesDB(game: game, credentials: credentials, force: force)
        }
        if let fields {
            activity = fields.isEmpty ? .nothingNew(title: title) : .updated(title: title, fields: fields)
            activityClearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.activity = nil
            }
        } else if case .failed(let message) = state {
            activity = .failed(title: title, message: message)
        } else {
            activity = nil
        }
    }

    func dismissActivity() {
        activityClearTask?.cancel()
        activity = nil
    }

    /// Fills in only the fields currently missing on `game`, unless
    /// `force` is set — a rescan of a locally-curated gamelist.xml
    /// shouldn't silently get overwritten by a scrape, and re-scraping
    /// the same game repeatedly shouldn't keep re-downloading art it
    /// already has.
    /// Returns the names of the fields it filled in, or `nil` if it failed.
    @discardableResult
    func scrapeUsingScreenScraper(game: Game, credentials: ScreenScraperCredentials, force: Bool = false) async -> [String]? {
        guard let systemeID = ScreenScraperSystemID.systemeID(for: CanonicalSystemID(game.systemCanonicalID)) else {
            state = .failed(String(localized: "ScreenScraper doesn't support this system yet."))
            return nil
        }

        state = .scraping
        let romURL = game.romAbsoluteURL
        var romFilename = romURL.lastPathComponent
        var romSizeBytes = (try? FileManager.default.attributesOfItem(atPath: romURL.path))?[.size] as? Int
        // A zipped cartridge is matched by the game inside, its own name
        // and size; an arcade romset is known by its zip.
        let system = CanonicalSystemID(game.systemCanonicalID)
        if SystemTaxonomy.definition(for: system)?.category != .arcade, let entry = ZipContents.singleEntry(of: romURL) {
            romFilename = (entry.name as NSString).lastPathComponent
            romSizeBytes = entry.size
        }

        do {
            let info = try await screenScraperClient.fetchGameInfo(
                romFilename: romFilename,
                romSizeBytes: romSizeBytes,
                systemeID: systemeID,
                credentials: credentials
            )
            let fields = try await apply(info, to: game, force: force)
            state = .idle
            return fields
        } catch let error as ScreenScraperError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed(error.localizedDescription)
        }
        return nil
    }

    @discardableResult
    func scrapeUsingTheGamesDB(game: Game, credentials: TheGamesDBCredentials, force: Bool = false) async -> [String]? {
        guard let platformID = TheGamesDBSystemID.platformID(for: CanonicalSystemID(game.systemCanonicalID)) else {
            state = .failed(String(localized: "TheGamesDB doesn't support this system yet."))
            return nil
        }

        state = .scraping

        do {
            let info = try await theGamesDBClient.fetchGameInfo(
                title: game.title,
                platformID: platformID,
                credentials: credentials,
                wantsScreenshot: force || game.titleScreenPath == nil
            )
            let fields = try await apply(info, to: game, force: force)
            state = .idle
            return fields
        } catch let error as TheGamesDBError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed(error.localizedDescription)
        }
        return nil
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

    /// Scrapes exactly these games (a multi-selection), whether or not they
    /// already have info — filling empty fields, or replacing them all with
    /// `force`. One game goes through `scrape(_:from:force:)` instead, for
    /// its more detailed status.
    func scrape(games: [Game], from source: ScraperSource, force: Bool = false) {
        if games.count == 1, let game = games.first {
            Task { await scrape(game, from: source, force: force) }
            return
        }
        dismissActivity()
        batchTask?.cancel()
        batchTask = Task { [weak self] in
            await self?.runBatch(games: games, source: source, onlyMissing: false, force: force)
        }
    }

    func cancelBatch() {
        batchTask?.cancel()
        batchTask = nil
        batchState = .idle
    }

    private func runBatch(games: [Game], source: ScraperSource, onlyMissing: Bool = true, force: Bool = false) async {
        let missing = onlyMissing ? games.filter { $0.gameDescription == nil } : games
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
                await scrapeUsingScreenScraper(game: game, credentials: credentials, force: force)
            case .theGamesDB(let credentials):
                await scrapeUsingTheGamesDB(game: game, credentials: credentials, force: force)
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
    /// Returns the (localized) names of the fields it changed.
    private func apply(_ info: ScrapedGameInfo, to game: Game, force: Bool) async throws -> [String] {
        var changed: [String] = []
        var changedProtectedField = false

        // Every field counts as protected now that rescans keep hand-set
        // release dates and ratings too.
        func fill<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Game, Value?>, with value: Value?, label: String) {
            guard force || game[keyPath: keyPath] == nil, let value, game[keyPath: keyPath] != value else { return }
            game[keyPath: keyPath] = value
            changed.append(label)
            changedProtectedField = true
        }

        fill(\.gameDescription, with: info.description, label: String(localized: "description"))
        fill(\.developer, with: info.developer, label: String(localized: "developer"))
        fill(\.publisher, with: info.publisher, label: String(localized: "publisher"))
        fill(\.genre, with: info.genre, label: String(localized: "genre"))
        fill(\.players, with: info.players, label: String(localized: "players"))
        fill(\.releaseDate, with: info.releaseDate, label: String(localized: "release date"))
        fill(\.rating, with: info.rating, label: String(localized: "rating"))

        // A cover the user picked is only replaced on an explicit "Replace
        // Existing Info".
        if (force || game.coverArtPath == nil), let remoteURL = info.coverArtURL {
            if let localURL = try? await downloadMedia(from: remoteURL, for: game, kind: .covers) {
                game.coverArtPath = localURL.path
                game.coverArtManuallySet = false
                changed.append(String(localized: "cover"))
            }
        }

        // Shown at the top of the detail panel; `titleScreenPath` holds a
        // screenshot or title screen, whichever the game has.
        if (force || game.titleScreenPath == nil), let remoteURL = info.screenshotURL {
            if let localURL = try? await downloadMedia(from: remoteURL, for: game, kind: .screenshots) {
                game.titleScreenPath = localURL.path
                changed.append(String(localized: "screenshot"))
            }
        }

        if changedProtectedField {
            game.metadataManuallyEdited = true
        }

        try? game.modelContext?.save()
        return changed
    }

    /// Into the media folder beside the games, where a rescan finds it too.
    private func downloadMedia(from remoteURL: URL, for game: Game, kind: MediaKind) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        return try game.storeMedia(data, fileExtension: remoteURL.pathExtension, kind: kind)
    }

    private static func message(for error: ScreenScraperError) -> String {
        switch error {
        case .notConfigured:
            String(localized: "ScreenScraper isn't configured yet — add your devID/devPassword in Settings.")
        case .noMatch:
            String(localized: "No match found on ScreenScraper for this ROM.")
        case .credentialsRejectedOrQuotaExceeded(let detail):
            String(localized: "ScreenScraper rejected the request (bad credentials or quota exceeded): \(detail)")
        case .network(let detail):
            String(localized: "Network error: \(detail)")
        case .malformedResponse(let detail):
            String(localized: "Unexpected response from ScreenScraper: \(detail)")
        }
    }

    private static func message(for error: TheGamesDBError) -> String {
        switch error {
        case .notConfigured:
            String(localized: "TheGamesDB isn't configured yet — add your API key in Settings.")
        case .noMatch:
            String(localized: "No match found on TheGamesDB for this ROM.")
        case .credentialsRejectedOrQuotaExceeded(let detail):
            String(localized: "TheGamesDB rejected the request (bad API key or quota exceeded): \(detail)")
        case .network(let detail):
            String(localized: "Network error: \(detail)")
        case .malformedResponse(let detail):
            String(localized: "Unexpected response from TheGamesDB: \(detail)")
        }
    }
}
