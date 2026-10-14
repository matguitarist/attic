import Foundation
import AtticModels
import AtticPersistence
import AtticLibraryScanning

/// What importing from another front-end's folder would bring, system by
/// system: counts of what the games lack and it has, and of what it has
/// at all (when replacing).
struct MediaImportPlan {
    struct Counts: Equatable {
        var covers = 0
        var screenshots = 0
        var videos = 0
        var manuals = 0
        var descriptions = 0

        var isEmpty: Bool { self == Counts() }
    }

    struct System: Identifiable {
        let id: CanonicalSystemID
        let name: String
        /// Games of the library found in the other front-end's gamelist.
        var matched = 0
        var missing = Counts()
        var available = Counts()
    }

    let folder: URL
    var systems: [System] = []
    /// Which entry each game takes: its path, the entry, and where its
    /// media goes.
    fileprivate var matches: [Match] = []

    fileprivate struct Match {
        let game: LibraryStore.GameMedia
        let entry: FrontEndMedia.Entry
        let hasManual: Bool
    }
}

extension ToolsCoordinator {
    /// Reads another front-end's gamelists (RetroBat's or Batocera's
    /// `roms` folder, or one system's folder in it) and shows what they'd
    /// fill in.
    func analyzeMediaImport(from folder: URL, scanCoordinator: ScanCoordinator, host: Host) async {
        guard !isBusy else { return }
        reportHost = host
        isAnalyzing = true
        let games = await scanCoordinator.gameMedia()
        let plan = await Task.detached(priority: .userInitiated) { Self.plan(folder: folder, games: games) }.value
        isAnalyzing = false
        guard !plan.systems.isEmpty else {
            outcome = Outcome(
                title: String(localized: "Import from Another Front-End"),
                message: String(localized: "No gamelist there lists your games. Choose the folder that holds each system's folder (RetroBat's or Batocera's roms folder), or one system's folder.")
            )
            return
        }
        report = .mediaImport(plan)
    }

    nonisolated private static func plan(folder: URL, games: [LibraryStore.GameMedia]) -> MediaImportPlan {
        var plan = MediaImportPlan(folder: folder)
        let gamesBySystem = Dictionary(grouping: games, by: \.system)
        for source in FrontEndMedia.systems(in: folder, wanted: Set(gamesBySystem.keys)) {
            var system = MediaImportPlan.System(id: source.system, name: SystemTaxonomy.definition(for: source.system)?.displayName ?? source.system.rawValue)
            for game in gamesBySystem[source.system] ?? [] {
                guard let entry = source.entries[FrontEndMedia.key(for: game.relativePath)] else { continue }
                let manual = MediaFolder.baseURL(forSystemFolder: game.systemFolder, romRelativePath: game.relativePath, kind: .manuals)
                    .appendingPathExtension("pdf")
                let hasManual = FileManager.default.fileExists(atPath: manual.path)
                system.matched += 1
                plan.matches.append(.init(game: game, entry: entry, hasManual: hasManual))
                if entry.cover != nil { system.available.covers += 1; if !game.hasCover { system.missing.covers += 1 } }
                if entry.screenshot != nil { system.available.screenshots += 1; if !game.hasScreenshot { system.missing.screenshots += 1 } }
                if entry.video != nil { system.available.videos += 1; if !game.hasVideo { system.missing.videos += 1 } }
                if entry.manual != nil { system.available.manuals += 1; if !hasManual { system.missing.manuals += 1 } }
                if entry.description != nil { system.available.descriptions += 1; if !game.hasDescription { system.missing.descriptions += 1 } }
            }
            if system.matched > 0 { plan.systems.append(system) }
        }
        plan.systems.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return plan
    }

    /// Copies the media into the Media folder (covers as HEIC when that's
    /// smaller) and fills in the games' info: what they lack, or all of it
    /// when `replacing`.
    func importMedia(_ plan: MediaImportPlan, replacing: Bool, romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        activity = Activity(title: String(localized: "Importing media…"), fraction: 0)
        let progress = { @Sendable (value: Double) -> Void in
            Task { @MainActor in self.activity?.fraction = value }
        }
        let (info, stored) = await Task.detached(priority: .userInitiated) {
            Self.copyMedia(plan.matches, replacing: replacing, progress: progress)
        }.value
        for url in stored { CoverArtThumbnailCache.shared.invalidate(url) }
        let changed = await scanCoordinator.applyImported(info, replacing: replacing)
        activity = nil
        outcome = Outcome(
            title: String(localized: "Import from Another Front-End"),
            message: changed == 0 && stored.isEmpty
                ? String(localized: "Your games already had all of it.")
                : String(localized: "\(changed) games got media or info, \(stored.count) files copied.")
        )
    }

    nonisolated private static func copyMedia(_ matches: [MediaImportPlan.Match], replacing: Bool,
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
            info[game.path] = imported
            progress(Double(index + 1) / Double(max(matches.count, 1)))
        }
        return (info, stored)
    }
}
