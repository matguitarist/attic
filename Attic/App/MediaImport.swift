import Foundation
import AtticModels
import AtticPersistence
import AtticLibraryScanning

/// What importing from another front-end's folder would bring, system by
/// system: counts of what the games lack and it has, and of what it has
/// at all (when replacing), and the games it has that the library doesn't.
struct MediaImportPlan {
    struct Counts: Equatable {
        var covers = 0
        var screenshots = 0
        var videos = 0
        var manuals = 0
        var logos = 0
        var descriptions = 0

        var isEmpty: Bool { self == Counts() }

        static func + (lhs: Counts, rhs: Counts) -> Counts {
            Counts(covers: lhs.covers + rhs.covers, screenshots: lhs.screenshots + rhs.screenshots, videos: lhs.videos + rhs.videos,
                   manuals: lhs.manuals + rhs.manuals, logos: lhs.logos + rhs.logos, descriptions: lhs.descriptions + rhs.descriptions)
        }
    }

    struct System: Identifiable {
        let id: CanonicalSystemID
        let name: String
        /// Games of the library found in the other front-end's gamelist.
        var matched = 0
        var missing = Counts()
        var available = Counts()
        /// Games the other front-end has and the library doesn't.
        var newGames: [FrontEndMedia.Entry] = []
        var newBytes: Int64 { newGames.reduce(0) { $0 + $1.bytes } }
        /// Media and info the new games would come with.
        var newGamesMedia = Counts()
    }

    let folder: URL
    var systems: [System] = []
    /// The other front-end's systems, read once.
    fileprivate var sources: [FrontEndMedia.SystemFolder] = []
}

/// A game of the library and the entry it takes.
private struct MediaImportMatch {
    let game: LibraryStore.GameMedia
    let entry: FrontEndMedia.Entry
    let hasManual: Bool
    let hasLogo: Bool
}

extension ToolsCoordinator {
    /// Reads another front-end's gamelists (RetroBat's or Batocera's
    /// `roms` folder, or one system's folder in it) and shows what they'd
    /// bring.
    func analyzeMediaImport(from folder: URL, scanCoordinator: ScanCoordinator, host: Host) async {
        guard !isBusy else { return }
        reportHost = host
        activity = Activity(title: String(localized: "Reading the other front-end's gamelists…"), fraction: 0)
        let progress = { @Sendable (value: Double, name: String) -> Void in
            Task { @MainActor in
                self.activity?.fraction = value
                self.activity?.detail = name
            }
        }
        let games = await scanCoordinator.gameMedia()
        let plan = await Task.detached(priority: .userInitiated) { Self.plan(folder: folder, games: games, progress: progress) }.value
        activity = nil
        guard !plan.systems.isEmpty else {
            outcome = Outcome(
                title: String(localized: "Import from Another Front-End"),
                message: String(localized: "No gamelist found there. Choose the folder that holds each system's folder (RetroBat's or Batocera's roms folder), or one system's folder.")
            )
            return
        }
        report = .mediaImport(plan)
    }

    nonisolated private static func plan(folder: URL, games: [LibraryStore.GameMedia],
                                         progress: @Sendable (Double, String) -> Void) -> MediaImportPlan {
        var plan = MediaImportPlan(folder: folder)
        plan.sources = FrontEndMedia.systems(in: folder, progress: progress)
        let gamesBySystem = Dictionary(grouping: games, by: \.system)
        for source in plan.sources {
            let mine = gamesBySystem[source.system] ?? []
            var system = MediaImportPlan.System(id: source.system, name: SystemTaxonomy.definition(for: source.system)?.displayName ?? source.system.rawValue)
            for match in matches(mine, source) {
                system.matched += 1
                let game = match.game
                let (missing, available) = counts(match.entry, hasCover: game.hasCover, hasScreenshot: game.hasScreenshot,
                                                  hasVideo: game.hasVideo, hasManual: match.hasManual, hasLogo: match.hasLogo,
                                                  hasDescription: game.hasDescription)
                system.missing = system.missing + missing
                system.available = system.available + available
            }
            let keys = Set(mine.map { FrontEndMedia.key(for: $0.relativePath) })
            system.newGames = installedSystems.contains(source.system.rawValue) ? []
                : source.entries.filter { !keys.contains($0.key) && $0.value.game != nil }.map(\.value)
                .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            for entry in system.newGames {
                system.newGamesMedia = system.newGamesMedia + counts(entry).available
            }
            if system.matched > 0 || !system.newGames.isEmpty { plan.systems.append(system) }
        }
        plan.systems.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return plan
    }

    /// Systems whose games another front-end lists as shortcuts to what
    /// its emulator installed: copying them would bring nothing to play.
    nonisolated private static let installedSystems: Set<String> = ["psvita", "ps3", "ps4"]

    nonisolated private static func matches(_ games: [LibraryStore.GameMedia], _ source: FrontEndMedia.SystemFolder) -> [MediaImportMatch] {
        games.compactMap { game in
            guard let entry = source.entries[FrontEndMedia.key(for: game.relativePath)] else { return nil }
            let manual = MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: .manuals)
                .appendingPathExtension("pdf")
            let logo = MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: .marquees)
            return MediaImportMatch(game: game, entry: entry, hasManual: FileManager.default.fileExists(atPath: manual.path),
                                    hasLogo: !MediaFolder.existingFiles(base: logo).isEmpty)
        }
    }

    /// What a game lacks that the entry has, and what the entry has.
    nonisolated private static func counts(_ entry: FrontEndMedia.Entry, hasCover: Bool = false, hasScreenshot: Bool = false, hasVideo: Bool = false,
                                           hasManual: Bool = false, hasLogo: Bool = false, hasDescription: Bool = false)
        -> (missing: MediaImportPlan.Counts, available: MediaImportPlan.Counts) {
        var missing = MediaImportPlan.Counts()
        var available = MediaImportPlan.Counts()
        if entry.cover != nil { available.covers += 1; if !hasCover { missing.covers += 1 } }
        if entry.screenshot != nil { available.screenshots += 1; if !hasScreenshot { missing.screenshots += 1 } }
        if entry.video != nil { available.videos += 1; if !hasVideo { missing.videos += 1 } }
        if entry.manual != nil { available.manuals += 1; if !hasManual { missing.manuals += 1 } }
        if entry.logo != nil { available.logos += 1; if !hasLogo { missing.logos += 1 } }
        if entry.description != nil { available.descriptions += 1; if !hasDescription { missing.descriptions += 1 } }
        return (missing, available)
    }

    /// Copies the chosen systems' games the library doesn't have, when
    /// asked, then their media into the Media folder (covers as HEIC when
    /// that's smaller) and the games' info: what they lack, or all of it
    /// when `replacing`.
    func importMedia(_ plan: MediaImportPlan, systems chosen: Set<CanonicalSystemID>, copyingGames: Bool, replacing: Bool,
                     romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        let sources = plan.sources.filter { chosen.contains($0.system) }
        var copiedGames = 0
        if copyingGames {
            let newGames = plan.systems.filter { chosen.contains($0.id) }.flatMap { system in system.newGames.map { (system.id, $0) } }
            if !newGames.isEmpty {
                activity = Activity(title: String(localized: "Copying games…"), fraction: 0)
                let progress = { @Sendable (value: Double, name: String) -> Void in
                    Task { @MainActor in
                        self.activity?.fraction = value
                        self.activity?.detail = name
                    }
                }
                copiedGames = await Task.detached(priority: .userInitiated) {
                    Self.copyGames(newGames, sources: sources, romsRoots: romsRoots, progress: progress)
                }.value
                // The new games join the library, to take their media.
                activity = Activity(title: String(localized: "Adding the games to the library…"))
                await scanCoordinator.scan(romsRootURLs: romsRoots)
            }
        }

        activity = Activity(title: String(localized: "Importing media…"), fraction: 0)
        let progress = { @Sendable (value: Double) -> Void in
            Task { @MainActor in self.activity?.fraction = value }
        }
        let games = await scanCoordinator.gameMedia()
        let (info, stored) = await Task.detached(priority: .userInitiated) {
            let bySystem = Dictionary(grouping: games, by: \.system)
            let matches = sources.flatMap { Self.matches(bySystem[$0.system] ?? [], $0) }
            return Self.copyMedia(matches, replacing: replacing, progress: progress)
        }.value
        for url in stored { CoverArtThumbnailCache.shared.invalidate(url) }
        let changed = await scanCoordinator.applyImported(info, replacing: replacing)
        activity = nil
        var lines: [String] = []
        if copyingGames { lines.append(String(localized: "\(copiedGames) games copied.")) }
        lines.append(changed == 0 && stored.isEmpty
            ? String(localized: "Your games already had all of it.")
            : String(localized: "\(changed) games got media or info, \(stored.count) files copied."))
        outcome = Outcome(title: String(localized: "Import from Another Front-End"), message: lines.joined(separator: " "))
    }

    nonisolated private static func copyGames(_ games: [(CanonicalSystemID, FrontEndMedia.Entry)], sources: [FrontEndMedia.SystemFolder],
                                              romsRoots: [URL], progress: @Sendable (Double, String) -> Void) -> Int {
        let sourceFolders = Dictionary(sources.map { ($0.system, $0.folder) }, uniquingKeysWith: { first, _ in first })
        var copied = 0
        for (index, (system, entry)) in games.enumerated() {
            progress(Double(index) / Double(max(games.count, 1)), entry.relativePath)
            guard let game = entry.game, let from = sourceFolders[system],
                  let destination = ROMImport.folder(for: system, romsRoots: romsRoots) else { continue }
            if FrontEndMedia.copyGame(game, from: from, to: destination) != nil { copied += 1 }
        }
        progress(1, "")
        return copied
    }

    nonisolated private static func copyMedia(_ matches: [MediaImportMatch], replacing: Bool,
                                              progress: @Sendable (Double) -> Void) -> ([String: LibraryStore.ImportedInfo], [URL]) {
        var info: [String: LibraryStore.ImportedInfo] = [:]
        var stored: [URL] = []
        func copy(_ source: URL?, _ kind: MediaKind, for game: LibraryStore.GameMedia) -> URL? {
            guard let source, let data = try? Data(contentsOf: source) else { return nil }
            if kind == .manuals {
                // A manual replaced goes to the Trash too, like the rest.
                let manual = MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: .manuals)
                    .appendingPathExtension("pdf")
                try? FileManager.default.trashItem(at: manual, resultingItemURL: nil)
            }
            // Covers are kept as HEIC when that's smaller.
            guard let url = try? MediaFolder.store(data, fileExtension: source.pathExtension.lowercased(),
                                                   forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: kind) else { return nil }
            stored.append(url)
            return url
        }
        for (index, match) in matches.enumerated() {
            let game = match.game
            let entry = match.entry
            var imported = LibraryStore.ImportedInfo(
                description: entry.description, developer: entry.developer, publisher: entry.publisher, genre: entry.genre,
                players: entry.players, releaseDate: entry.releaseDate, rating: entry.rating
            )
            if replacing || !game.hasCover { imported.coverPath = copy(entry.cover, .covers, for: game)?.path }
            if replacing || !game.hasScreenshot { imported.screenshotPath = copy(entry.screenshot, .screenshots, for: game)?.path }
            if replacing || !game.hasVideo { imported.videoPath = copy(entry.video, .videos, for: game)?.path }
            if replacing || !match.hasManual { _ = copy(entry.manual, .manuals, for: game) }
            if replacing || !match.hasLogo { _ = copy(entry.logo, .marquees, for: game) }
            info[game.path] = imported
            progress(Double(index + 1) / Double(max(matches.count, 1)))
        }
        return (info, stored)
    }
}
