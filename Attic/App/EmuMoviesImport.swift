import Foundation
import AtticModels
import AtticPersistence
import AtticLibraryScanning
import AtticEmulation

/// What EmuMovies has for the library's systems, looked up one system at
/// a time as they're picked in the report: the artwork packs in its
/// folder, the manuals for its games, and its video.
@Observable
@MainActor
final class EmuMoviesPlan {
    struct System: Identifiable {
        let id: CanonicalSystemID
        let name: String
        /// The system's folder in ROMs, where its media goes.
        let systemFolder: URL
        let games: Int
        /// The packs Attic can use, and the one picked for each kind.
        var packs: [EmuMovies.Pack] = []
        var chosen: [MediaKind: EmuMovies.Pack] = [:]
        /// Games without each kind of media.
        var missing: [MediaKind: Int] = [:]
        /// Games whose picture of each kind is small, by their paths.
        var lowQuality: [MediaKind: Set<String>] = [:]
        /// The manuals folder, and the manual for each game it has one for.
        var manualsFolder: String?
        var manuals: [String: EmuMovies.Entry] = [:]
        var missingManuals = 0
        var video: EmuMovies.Entry?
        var hasVideo = false
        /// Whether the system's video is below HD.
        var videoIsLowQuality = false
        /// Each game's video, by its path.
        var snaps: [String: Snap] = [:]
    }

    struct Snap {
        /// The folder it's in.
        let folder: String
        let file: EmuMovies.Entry
        /// Whether the game has no video yet, or a small one.
        var missing = false
        var lowQuality = false
    }

    enum Lookup: Equatable {
        case waiting, looking, done
        case failed(String)
    }

    private(set) var systems: [System]
    private(set) var lookups: [CanonicalSystemID: Lookup] = [:]
    /// Whether split archives (`….part1.rar`) can be opened: they need
    /// `unar`, from Homebrew.
    let unar: URL?
    let server: EmuMoviesServer
    private let games: [CanonicalSystemID: [LibraryStore.GameMedia]]
    private var queue: [CanonicalSystemID] = []
    private var worker: Task<Void, Never>?
    /// The artwork, manuals and videos folders hold every system's: read
    /// once per look.
    private var roots: [String: [EmuMovies.Entry]] = [:]
    /// The systems' folders as last read, kept on disk.
    private var listings = EmuMovies.ListingCache.load(from: EmuMoviesPlan.listingsURL)
    private static let listingsURL = URL.cachesDirectory.appending(path: "Attic/EmuMovies Listings.json")

    nonisolated static let kinds: [MediaKind] = [.covers, .boxes3D, .physicalMedia, .logos, .fanart, .screenshots]

    init(server: EmuMoviesServer, games: [LibraryStore.GameMedia]) {
        self.server = server
        unar = ["/opt/homebrew/bin/unar", "/usr/local/bin/unar"].map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        let bySystem = Dictionary(grouping: games, by: \.system).filter { EmuMovies.names(for: $0.key) != nil }
        self.games = bySystem
        systems = bySystem.map { id, games in
            System(id: id, name: ToolsCoordinator.name(of: id), systemFolder: games[0].systemFolder, games: games.count)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func system(_ id: CanonicalSystemID) -> System? { systems.first { $0.id == id } }

    /// Looks the system up, after those asked for before it.
    func lookUp(_ id: CanonicalSystemID) {
        switch lookups[id] {
        case .done?, .looking?, .waiting?: return
        default: break
        }
        lookups[id] = .waiting
        queue.append(id)
        guard worker == nil else { return }
        worker = Task {
            while !queue.isEmpty, !Task.isCancelled {
                let next = queue.removeFirst()
                lookups[next] = .looking
                do {
                    let found = try await details(of: next)
                    if let index = systems.firstIndex(where: { $0.id == next }) { systems[index] = found }
                    lookups[next] = .done
                    listings.save(to: Self.listingsURL)
                } catch {
                    lookups[next] = Task.isCancelled ? nil
                        : .failed((error as? EmuMoviesServer.Failure).map(EmuMoviesSettingsView.message) ?? error.localizedDescription)
                }
            }
            worker = nil
        }
    }

    /// Stops looking the system up, if it hasn't been yet.
    func forget(_ id: CanonicalSystemID) {
        guard lookups[id] == .waiting else { return }
        queue.removeAll { $0 == id }
        lookups[id] = nil
    }

    /// Stops all lookups, when the report closes.
    func stop() {
        queue.removeAll()
        worker?.cancel()
        worker = nil
        for (id, lookup) in lookups where lookup != .done { lookups[id] = nil }
    }

    private func root(_ path: String) async throws -> [EmuMovies.Entry] {
        if let entries = roots[path] { return entries }
        let entries = try await server.list(path)
        roots[path] = entries
        return entries
    }

    /// A folder in `root`, read again only when its date there changed.
    private func folder(_ name: String, in root: String) async throws -> [EmuMovies.Entry]? {
        guard let folder = try await self.root(root).first(where: { $0.isFolder && $0.name == name }) else { return nil }
        let path = root + name + "/"
        if let entries = listings.entries(of: path, folder: folder) { return entries }
        let entries = try await server.list(path)
        listings.store(entries, of: path, folder: folder)
        return entries
    }

    private func details(of id: CanonicalSystemID) async throws -> System {
        guard var system = system(id), let names = EmuMovies.names(for: id) else { throw CancellationError() }
        let games = games[id] ?? []
        if let folder = names.artwork, let entries = try await self.folder(folder, in: EmuMovies.artworkFolder) {
            system.packs = EmuMovies.packs(in: entries)
            system.chosen = EmuMovies.bestPacks(system.packs, canOpenSplit: unar != nil)
            for kind in Self.kinds {
                system.missing[kind] = games.filter { !ToolsCoordinator.has(kind, $0) }.count
            }
            system.lowQuality = await Task.detached(priority: .userInitiated) {
                Dictionary(uniqueKeysWithValues: Self.kinds.map { kind in
                    (kind, Set(games.filter { ToolsCoordinator.isLowQuality(kind, $0) }.map(\.path)))
                })
            }.value
        }
        if let prefix = names.manuals,
           let folder = EmuMovies.manualsFolder(in: try await root(EmuMovies.manualsFolder), prefix: prefix),
           let entries = try await self.folder(folder, in: EmuMovies.manualsFolder) {
            let files = entries.filter { !$0.isFolder && $0.name.lowercased().hasSuffix(".pdf") }
            let byName = Dictionary(files.map { (($0.name as NSString).deletingPathExtension, $0) }, uniquingKeysWith: { first, _ in first })
            let matches = EmuMovies.match(games: games.map(ToolsCoordinator.gameName), files: Array(byName.keys))
            system.manualsFolder = folder
            for game in games {
                guard let file = matches[ToolsCoordinator.gameName(game)].flatMap({ byName[$0] }) else { continue }
                system.manuals[game.path] = file
                if !ToolsCoordinator.hasManual(game) { system.missingManuals += 1 }
            }
        }
        let prefixes = EmuMovies.videoSnapsPrefixes(for: id)
        if !prefixes.isEmpty {
            // The best folder's file wins when two have one for a game.
            var byName: [String: Snap] = [:]
            for folder in EmuMovies.videoSnapsFolders(in: try await root(EmuMovies.videoSnapsFolder), prefixes: prefixes) {
                for file in try await self.folder(folder, in: EmuMovies.videoSnapsFolder) ?? []
                where !file.isFolder && MediaFolder.videoExtensions.contains((file.name as NSString).pathExtension.lowercased()) {
                    let name = (file.name as NSString).deletingPathExtension
                    if byName[name] == nil { byName[name] = Snap(folder: folder, file: file) }
                }
            }
            let matches = EmuMovies.match(games: games.map(ToolsCoordinator.gameName), files: Array(byName.keys))
            for game in games {
                guard var snap = matches[ToolsCoordinator.gameName(game)].flatMap({ byName[$0] }) else { continue }
                snap.missing = !ToolsCoordinator.has(.videos, game)
                if !snap.missing, let current = ToolsCoordinator.existing(.videos, game), let size = await MediaQuality.size(ofVideo: current) {
                    snap.lowQuality = MediaQuality.isLowQuality(video: size)
                }
                system.snaps[game.path] = snap
            }
        }
        if let prefix = names.video {
            system.video = EmuMovies.systemVideo(in: try await root(EmuMovies.videosFolder), prefix: prefix)
            let current = MediaFolder.systemArt(.video, forSystemFolder: system.systemFolder)
            system.hasVideo = current != nil
            // Platform videos are HD.
            if let current, let size = await MediaQuality.size(ofVideo: current) {
                system.videoIsLowQuality = min(size.width, size.height) < 720
            }
        }
        return system
    }
}

/// What to get, from the report.
struct EmuMoviesChoice {
    /// What to do with the media games already have.
    enum Replacing: String {
        /// Only games missing something get it.
        case keep
        /// Small pictures and videos are replaced by EmuMovies' when it's
        /// sharper; the rest is kept.
        case lowQuality
        case all
    }

    var systems: Set<CanonicalSystemID>
    var kinds: Set<MediaKind>
    var manuals: Bool
    var videos: Bool
    var snaps: Bool
    var replacing: Replacing
    var packs: [CanonicalSystemID: [MediaKind: EmuMovies.Pack]]
}

extension ToolsCoordinator {
    /// Shows the library's systems EmuMovies has media for; each is looked
    /// up on its server when it's picked.
    func analyzeEmuMovies(server: EmuMoviesServer, scanCoordinator: ScanCoordinator, host: Host) async {
        guard !isBusy else { return }
        reportHost = host
        let plan = EmuMoviesPlan(server: server, games: await scanCoordinator.gameMedia())
        guard !plan.systems.isEmpty else {
            outcome = Outcome(title: String(localized: "Get Media from EmuMovies"),
                              message: String(localized: "EmuMovies has nothing for the systems in your library."))
            return
        }
        report = .emuMovies(plan)
    }

    nonisolated static func name(of system: CanonicalSystemID) -> String {
        SystemTaxonomy.definition(for: system)?.displayName ?? system.rawValue
    }

    /// A game's ROM name without its folder or extension, what EmuMovies'
    /// files are named after.
    nonisolated static func gameName(_ game: LibraryStore.GameMedia) -> String {
        ((game.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    nonisolated static func has(_ kind: MediaKind, _ game: LibraryStore.GameMedia) -> Bool {
        switch kind {
        case .covers: game.hasCover
        case .screenshots: game.hasScreenshot
        case .videos: game.hasVideo || !MediaFolder.existingFiles(base: MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: .videos)).isEmpty
        default: !MediaFolder.existingFiles(base: MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: kind)).isEmpty
        }
    }

    nonisolated private static func manualURL(_ game: LibraryStore.GameMedia) -> URL {
        MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: .manuals).appendingPathExtension("pdf")
    }

    /// The game's file of `kind` in its media folder.
    nonisolated static func existing(_ kind: MediaKind, _ game: LibraryStore.GameMedia) -> URL? {
        MediaFolder.existingFiles(base: MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: kind)).first
    }

    /// Whether the game's picture of `kind` is small enough to be worth
    /// replacing by a sharper one.
    nonisolated static func isLowQuality(_ kind: MediaKind, _ game: LibraryStore.GameMedia) -> Bool {
        guard let url = existing(kind, game), let size = MediaQuality.size(ofImage: url) else { return false }
        return MediaQuality.isLowQuality(image: size, kind: kind)
    }

    nonisolated static func hasManual(_ game: LibraryStore.GameMedia) -> Bool {
        FileManager.default.fileExists(atPath: manualURL(game).path)
    }

    // MARK: - Getting it

    /// Covers, logos and the like are scaled to fit this, about the size a
    /// 4K screen shows a cover at, and saved as HEIC. Fan art fills the
    /// screen, so it's kept at full HD.
    nonisolated static func maxPixelSize(for kind: MediaKind) -> Int {
        kind == .fanart ? 1920 : 1400
    }

    /// Downloads what was chosen and puts it in place: each pack's files
    /// for the games that need them, manuals, game and system videos.
    func getEmuMovies(_ plan: EmuMoviesPlan, choice: EmuMoviesChoice, server: EmuMoviesServer, romsRoots: [URL], scanCoordinator: ScanCoordinator) {
        plan.stop()
        let task = Task {
            activity = Activity(title: String(localized: "Getting media from EmuMovies…"), fraction: 0)
            let games = Dictionary(grouping: await scanCoordinator.gameMedia(), by: \.system)
            let jobs = Self.jobs(plan, choice: choice, games: games)
            let total = max(jobs.reduce(0) { $0 + $1.bytes }, 1)
            var done: Int64 = 0
            var info: [String: LibraryStore.ImportedInfo] = [:]
            var stored: [URL] = []
            var problems: [String] = []
            /// Files EmuMovies had no sharper version of, left as they were.
            var kept = 0
            let cache = URL.cachesDirectory.appending(path: "Attic/EmuMovies", directoryHint: .isDirectory)

            for job in jobs {
                if Task.isCancelled { break }
                let base = done
                let size = job.bytes
                let progress = { @Sendable (bytes: Int64) -> Void in
                    let fraction = Double(base + min(bytes, size)) / Double(total)
                    Task { @MainActor in self.activity?.fraction = fraction }
                }
                activity?.detail = job.title
                do {
                    switch job.work {
                    case .pack(let pack, let kind, let systemGames, let improving):
                        let result = try await Self.getPack(pack, kind: kind, folder: job.folder, games: systemGames, improving: improving,
                                                            server: server, cache: cache, unar: plan.unar, progress: progress) { name in
                            self.activity?.detail = "\(job.title) — \(name)"
                        }
                        stored += result.stored
                        kept += result.kept
                        for (path, url) in result.byGame {
                            if kind == .covers { info[path, default: .init()].coverPath = url.path }
                            if kind == .screenshots { info[path, default: .init()].screenshotPath = url.path }
                        }
                    case .manual(let file, let game):
                        let destination = Self.manualURL(game)
                        let download = cache.appending(path: UUID().uuidString + ".pdf")
                        try await server.download(job.folder + file.name, to: download, progress: progress)
                        try? FileManager.default.trashItem(at: destination, resultingItemURL: nil)
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: download, to: destination)
                        stored.append(destination)
                    case .snap(let file, let game, let onlyIfBetter):
                        let base = MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: .videos)
                        let destination = base.appendingPathExtension((file.name as NSString).pathExtension.lowercased())
                        let download = cache.appending(path: UUID().uuidString + "." + destination.pathExtension)
                        try await server.download(job.folder + file.name, to: download, progress: progress)
                        if onlyIfBetter, let current = Self.existing(.videos, game), await !Self.isBetterVideo(download, than: current) {
                            try? FileManager.default.removeItem(at: download)
                            kept += 1
                            break
                        }
                        for old in MediaFolder.existingFiles(base: base) { try? FileManager.default.trashItem(at: old, resultingItemURL: nil) }
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: download, to: destination)
                        stored.append(destination)
                        info[game.path, default: .init()].videoPath = destination.path
                    case .video(let file, let systemFolder, let onlyIfBetter):
                        let download = cache.appending(path: file.name)
                        try await server.download(EmuMovies.videosFolder + file.name, to: download, progress: progress)
                        if onlyIfBetter, let current = MediaFolder.systemArt(.video, forSystemFolder: systemFolder),
                           await !Self.isBetterVideo(download, than: current) {
                            try? FileManager.default.removeItem(at: download)
                            kept += 1
                            break
                        }
                        let url = try MediaFolder.setSystemArt(.video, to: download, forSystemFolder: systemFolder)
                        try? FileManager.default.removeItem(at: download)
                        url.map { stored.append($0) }
                    }
                } catch EmuMoviesServer.Failure.cancelled {
                    break
                } catch is CancellationError {
                    break
                } catch {
                    let message = (error as? EmuMoviesServer.Failure).map(EmuMoviesSettingsView.message) ?? error.localizedDescription
                    problems.append("\(job.title): \(message)")
                }
                done += job.bytes
            }

            for url in stored { CoverArtThumbnailCache.shared.invalidate(url) }
            let changed = await scanCoordinator.applyImported(info, replacing: true)
            if changed > 0 || !stored.isEmpty {
                activity = Activity(title: String(localized: "Updating the library…"))
                await scanCoordinator.scan(romsRootURLs: romsRoots, only: choice.systems)
            }
            activity = nil
            cancelActivity = nil
            var lines = [Task.isCancelled
                ? String(localized: "Stopped. \(stored.count) files were put in place before that.")
                : String(localized: "\(stored.count) files put in place.")]
            if kept > 0 { lines.append(String(localized: "\(kept) files were kept: EmuMovies' weren't sharper.")) }
            if !problems.isEmpty { lines.append(problems.joined(separator: "\n")) }
            AppLog.post(.info, "EmuMovies: \(stored.count) files put in place.")
            outcome = Outcome(title: String(localized: "Get Media from EmuMovies"), message: lines.joined(separator: "\n\n"))
        }
        cancelActivity = { task.cancel() }
    }

    nonisolated private static func isBetterVideo(_ new: URL, than old: URL) async -> Bool {
        guard let newSize = await MediaQuality.size(ofVideo: new) else { return false }
        guard let oldSize = await MediaQuality.size(ofVideo: old) else { return true }
        return MediaQuality.isBetter(newSize, than: oldSize)
    }

    private struct Job {
        enum Work {
            /// With the paths of the games that only get a sharper picture.
            case pack(EmuMovies.Pack, MediaKind, [LibraryStore.GameMedia], improving: Set<String>)
            case manual(EmuMovies.Entry, LibraryStore.GameMedia)
            case snap(EmuMovies.Entry, LibraryStore.GameMedia, onlyIfBetter: Bool)
            case video(EmuMovies.Entry, URL, onlyIfBetter: Bool)
        }
        let title: String
        /// The server folder it's in, ending with a slash.
        let folder: String
        let bytes: Int64
        let work: Work
    }

    private static func jobs(_ plan: EmuMoviesPlan, choice: EmuMoviesChoice, games: [CanonicalSystemID: [LibraryStore.GameMedia]]) -> [Job] {
        var jobs: [Job] = []
        for system in plan.systems where choice.systems.contains(system.id) && plan.lookups[system.id] == .done {
            let mine = games[system.id] ?? []
            let packs = choice.packs[system.id] ?? system.chosen
            for kind in EmuMoviesPlan.kinds where choice.kinds.contains(kind) {
                guard let pack = packs[kind], let folder = EmuMovies.names(for: system.id)?.artwork else { continue }
                // Only for the games that need it.
                let improving = choice.replacing == .lowQuality ? system.lowQuality[kind] ?? [] : []
                let needing = choice.replacing == .all ? mine : mine.filter { !has(kind, $0) || improving.contains($0.path) }
                guard !needing.isEmpty else { continue }
                jobs.append(Job(title: "\(system.name) · \(kind.title)", folder: EmuMovies.artworkFolder + folder + "/",
                                bytes: pack.size, work: .pack(pack, kind, needing, improving: improving)))
            }
            if choice.manuals, let folder = system.manualsFolder {
                for game in mine {
                    guard let file = system.manuals[game.path], choice.replacing == .all || !hasManual(game) else { continue }
                    jobs.append(Job(title: "\(system.name) · \(gameName(game))", folder: EmuMovies.manualsFolder + folder + "/",
                                    bytes: file.size, work: .manual(file, game)))
                }
            }
            if choice.snaps {
                for game in mine {
                    guard let snap = system.snaps[game.path] else { continue }
                    let improving = choice.replacing == .lowQuality && snap.lowQuality
                    guard choice.replacing == .all || snap.missing || improving else { continue }
                    jobs.append(Job(title: "\(system.name) · \(gameName(game))", folder: EmuMovies.videoSnapsFolder + snap.folder + "/",
                                    bytes: snap.file.size, work: .snap(snap.file, game, onlyIfBetter: improving)))
                }
            }
            let improvingVideo = choice.replacing == .lowQuality && system.hasVideo && system.videoIsLowQuality
            if choice.videos, let video = system.video, choice.replacing == .all || !system.hasVideo || improvingVideo {
                jobs.append(Job(title: "\(system.name) · \(String(localized: "System Video"))", folder: EmuMovies.videosFolder,
                                bytes: video.size, work: .video(video, system.systemFolder, onlyIfBetter: improvingVideo)))
            }
        }
        return jobs
    }

    /// Downloads a pack (or carries on with one partly downloaded), opens
    /// it, and stores the files of the games that match. The pack is
    /// deleted after.
    private static func getPack(_ pack: EmuMovies.Pack, kind: MediaKind, folder: String, games: [LibraryStore.GameMedia], improving: Set<String>,
                                server: EmuMoviesServer, cache: URL, unar: URL?, progress: @escaping @Sendable (Int64) -> Void,
                                status: @MainActor (String) -> Void) async throws -> (stored: [URL], byGame: [String: URL], kept: Int) {
        var downloaded: Int64 = 0
        var archives: [URL] = []
        defer { for archive in archives { try? FileManager.default.removeItem(at: archive) } }
        for file in pack.files {
            let destination = cache.appending(path: file)
            archives.append(destination)
            let offset = downloaded
            try await server.download(folder + file, to: destination) { progress(offset + $0) }
            downloaded += MediaFolder.fileSize(destination)
        }

        status(String(localized: "opening"))
        let unpacked = cache.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: unpacked) }
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let (first, split) = (archives[0], pack.isSplit)
        try await Task.detached { try unpack(first, split: split, to: unpacked, unar: unar) }.value

        return await Task.detached(priority: .userInitiated) {
            let files = (FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { ["png", "jpg", "jpeg", "webp", "heic", "gif", "bmp"].contains($0.pathExtension.lowercased()) }
            let byName = Dictionary(files.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
            let matches = EmuMovies.match(games: games.map(gameName), files: Array(byName.keys))
            var stored: [URL] = []
            var byGame: [String: URL] = [:]
            var kept = 0
            for game in games {
                guard let file = matches[gameName(game)].flatMap({ byName[$0] }), let data = try? Data(contentsOf: file) else { continue }
                // A game with a small picture only gets a sharper one.
                if improving.contains(game.path), let current = existing(kind, game).flatMap(MediaQuality.size(ofImage:)),
                   !(MediaQuality.size(ofImageData: data).map { MediaQuality.isBetter($0, than: current) } ?? false) {
                    kept += 1
                    continue
                }
                guard let url = try? MediaFolder.store(data, fileExtension: file.pathExtension, forSystemFolder: game.systemFolder,
                                                       romRelativePath: game.relativePath, kind: kind, maxPixelSize: maxPixelSize(for: kind)) else { continue }
                stored.append(url)
                byGame[game.path] = url
            }
            return (stored, byGame, kept)
        }.value
    }

    /// Opens an archive: zip, 7z and rar with macOS's `bsdtar`, a split
    /// rar with `unar`.
    nonisolated private static func unpack(_ archive: URL, split: Bool, to folder: URL, unar: URL?) throws {
        let process = Process()
        if split {
            guard let unar else { throw EmuMoviesServer.Failure.transfer(String(localized: "Split archives need unar: brew install unar")) }
            process.executableURL = unar
            process.arguments = ["-quiet", "-force-overwrite", "-no-directory", "-output-directory", folder.path, archive.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
            process.arguments = ["-xf", archive.path, "-C", folder.path]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }
}
