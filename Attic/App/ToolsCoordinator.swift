import SwiftUI
import AtticModels
import AtticPersistence
import AtticLibraryScanning
import AtticEmulation

/// The Tools menu's work: the Tidy Up and Compress Games reports, a
/// single game's compression or conversion back, and their progress,
/// shared by the library window and Settings.
@Observable
@MainActor
final class ToolsCoordinator {
    enum Report: Identifiable {
        case tidy(MediaTidyPlan)
        case compress(GameCompressionPlan)
        case verify(VerifyReport)
        case mediaImport(MediaImportPlan)

        var id: String {
            switch self {
            case .tidy: "tidy"
            case .compress: "compress"
            case .verify: "verify"
            case .mediaImport: "mediaImport"
            }
        }
    }

    /// Where a report shows: the window it was asked for from.
    enum Host { case library, settings, help }

    struct Activity: Equatable {
        let title: String
        var detail = ""
        var fraction: Double?
    }

    var report: Report?
    var reportHost: Host = .library
    var isAnalyzing = false
    var activity: Activity?
    /// What the last run did, for an alert.
    struct Outcome: Equatable {
        let title: String
        let message: String
    }
    var outcome: Outcome?
    private(set) var chdman = CHDConversion.findCHDMan()
    private(set) var isInstallingCHDMan = false
    var chdmanError: String?

    var isBusy: Bool { isAnalyzing || activity != nil }

    /// When a system's games were last checked, and against which DATs.
    struct Verification: Codable, Equatable {
        let date: Date
        let dats: [String]
    }

    private static let verificationsKey = "verifications"

    /// The last verification of each system, by its ID.
    private(set) var verifications: [String: Verification] = {
        guard let data = UserDefaults.standard.data(forKey: ToolsCoordinator.verificationsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Verification].self, from: data)) ?? [:]
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(verifications), forKey: Self.verificationsKey) }
    }

    // MARK: - Reports

    /// A dry run of Tidy Up: works out what it would do and shows it,
    /// changing nothing.
    func analyzeTidy(romsRoots: [URL], from host: Host) async {
        guard !isBusy else { return }
        reportHost = host
        isAnalyzing = true
        let plan = await Task.detached(priority: .userInitiated) { MediaTidier.plan(romsRoots: romsRoots) }.value
        isAnalyzing = false
        guard !plan.isEmpty else {
            outcome = Outcome(title: String(localized: "Tidy Up"), message: String(localized: "Everything's already in place."))
            return
        }
        report = .tidy(plan)
    }

    func tidy(_ plan: MediaTidyPlan, romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        activity = Activity(title: String(localized: "Tidying up…"), fraction: 0)
        let progress = { @Sendable (value: Double) -> Void in
            Task { @MainActor in self.activity?.fraction = value }
        }
        _ = await Task.detached(priority: .userInitiated) { MediaTidier.apply(plan, progress: progress) }.value
        // Media and gamelists moved: the library picks up their new places.
        await scanCoordinator.scan(romsRootURLs: romsRoots)
        activity = nil
    }

    /// Looks for games that could take less room, and shows them.
    func analyzeCompression(romsRoots: [URL], from host: Host) async {
        guard !isBusy else { return }
        reportHost = host
        isAnalyzing = true
        refreshCHDMan()
        let plan = await Task.detached(priority: .userInitiated) { GameCompressionPlan.plan(romsRoots: romsRoots) }.value
        isAnalyzing = false
        guard !plan.isEmpty else {
            outcome = Outcome(title: String(localized: "Compress Games"), message: String(localized: "Every game that can be compressed already is."))
            return
        }
        report = .compress(plan)
    }

    func compress(_ plan: GameCompressionPlan, romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        activity = Activity(title: String(localized: "Compressing games…"), fraction: 0)
        let chdman = chdman
        let progress = { @Sendable (value: Double, name: String) -> Void in
            Task { @MainActor in
                self.activity?.fraction = value
                self.activity?.detail = name
            }
        }
        let result = await Task.detached(priority: .userInitiated) {
            GameCompressionPlan.apply(plan, chdman: chdman, progress: progress)
        }.value
        await scanCoordinator.scan(romsRootURLs: romsRoots)
        activity = nil
        outcome = Outcome(title: String(localized: "Compress Games"), message: Self.summary(of: result))
    }

    // MARK: - Verify

    /// What checking the library against the DATs found.
    struct VerifyReport {
        struct Game: Hashable {
            let path: String
            let relativePath: String
            let system: CanonicalSystemID
            let title: String
            let datName: String?
            /// What's wrong with an arcade set.
            var detail: String?

            var stem: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }

            /// Worth renaming without a second look: No-Intro's name
            /// doesn't add a release the game may not be (the same data
            /// is sometimes listed as a prototype or a re-release too).
            var isPlainRename: Bool {
                guard let datName else { return false }
                let tags = { (name: String) in Set(name.matches(of: #/\(([^)]*)\)/#).map { String($0.output.1).lowercased() }) }
                let added = tags(datName).subtracting(tags(stem))
                let releases = ["proto", "beta", "demo", "sample", "virtual console", "classic mini", "switch online", "collection", "unl", "pirate", "aftermarket", "program", "kiosk", "competition"]
                return !added.contains { tag in releases.contains { tag.contains($0) } }
            }
        }

        struct System: Identifiable {
            let id: CanonicalSystemID
            let name: String
            var verified = 0
            var verifiedGames: [Game] = []
            /// Verified, but filed under a name of their own.
            var renamed: [Game] = []
            var differs: [Game] = []
            var unknown: [Game] = []
            /// Arcade sets missing chips or their disc image.
            var incomplete: [Game] = []
            /// Arcade romsets, discs: not checked.
            var skipped = 0
        }

        var systems: [System] = []
        /// Systems in the library with no DAT, and how many games each has.
        var withoutDAT: [(name: String, games: Int)] = []
        /// DATs Attic couldn't tie to a system.
        var unmatchedDATs: [String] = []
        var datCount = 0
        /// The one system checked, when it wasn't the whole library.
        var system: CanonicalSystemID?
        /// The DATs that one system was checked against.
        var systemDATs: [String] = []
        /// Arcade DATs that would check games here, and aren't there.
        var missingArcadeDATs: [ArcadeVerifier.Source] = []
        /// Arcade DATs that checked games here, by the name they go by,
        /// to update.
        var arcadeDATs: [ArcadeVerifier.Source: String] = [:]
    }

    /// Whether a system's games are in a DAT: not hack folders.
    nonisolated static func canVerify(_ system: CanonicalSystemID) -> Bool {
        ROMHacks.base(of: system) == nil
    }

    nonisolated static func isArcade(_ system: CanonicalSystemID) -> Bool {
        SystemTaxonomy.definition(for: system)?.category == .arcade
    }

    /// The arcade DAT for a system's emulator: FinalBurn Neo's for the
    /// boards it runs, MAME's for the rest (Flycast and Supermodel take
    /// MAME's sets).
    nonisolated static func arcadeSource(for system: CanonicalSystemID) -> ArcadeVerifier.Source {
        EmulatorCatalog.recommendation(for: system)?.recommendedCore?.coreIdentifier == "fbneo_libretro" ? .fbneo : .mame
    }

    nonisolated private static var arcadeCache: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Attic/ArcadeDATs")
    }

    /// Checks every game (or one system's) against the DATs in the
    /// Emulation folder's DATs folder, keeps each verdict on its game, and
    /// shows what was found.
    func verify(datsFolder: URL, scanCoordinator: ScanCoordinator, from host: Host, system: CanonicalSystemID? = nil) async {
        guard !isBusy else { return }
        reportHost = host
        try? FileManager.default.createDirectory(at: datsFolder, withIntermediateDirectories: true)
        activity = Activity(title: String(localized: "Reading DAT files…"))
        let files = await scanCoordinator.gameFiles().filter { (system == nil || $0.system == system) && Self.canVerify($0.system) }
        // Arcade sets by name: only those in the library are read from
        // MAME's list, which has some 50,000.
        let wanted = Set(files.filter { Self.isArcade($0.system) }.map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent })
        let biosDirectory = datsFolder.deletingLastPathComponent().appending(path: "BIOS", directoryHint: .isDirectory)
        let (verifier, arcade) = await Task.detached(priority: .userInitiated) {
            (DATVerifier.load(from: datsFolder),
             wanted.isEmpty ? ArcadeVerifier.none : ArcadeVerifier.load(from: datsFolder, wanted: wanted, cacheDirectory: Self.arcadeCache))
        }.value
        activity = Activity(title: String(localized: "Verifying games…"), fraction: 0)
        let progress = { @Sendable (value: Double, name: String) -> Void in
            Task { @MainActor in
                self.activity?.fraction = value
                self.activity?.detail = name
            }
        }
        let checks = await Task.detached(priority: .userInitiated) { () -> [String: DATVerifier.Check?] in
            var checks: [String: DATVerifier.Check?] = [:]
            for (index, file) in files.enumerated() {
                if index % 20 == 0 { progress(Double(index) / Double(max(files.count, 1)), file.title) }
                let url = URL(fileURLWithPath: file.path)
                if Self.isArcade(file.system) {
                    guard !arcade.sources.isEmpty else { continue }
                    checks[file.path] = .some(arcade.check(url, preferring: Self.arcadeSource(for: file.system), biosDirectory: biosDirectory))
                    continue
                }
                guard verifier.systems.contains(file.system) else { continue }
                checks[file.path] = .some(verifier.check(url, system: file.system))
            }
            return checks
        }.value
        await scanCoordinator.saveDATVerdicts(checks.mapValues { (verdict: $0?.verdict.rawValue, name: $0?.name, detail: $0?.detail) })
        activity = nil
        // Each system checked, with what it was checked against.
        let now = Date()
        for checked in Set(files.filter { checks[$0.path] != nil }.map(\.system)) {
            let dats = Self.isArcade(checked)
                ? arcade.name(of: Self.arcadeSource(for: checked)).map { [$0] } ?? arcade.names
                : verifier.sets.filter { $0.system == checked }.map(\.name)
            verifications[checked.rawValue] = Verification(date: now, dats: dats)
        }
        var result = Self.report(files: files, checks: checks, verifier: verifier)
        result.system = system
        result.datCount += arcade.names.count
        if let system {
            // Only what concerns that system: its DAT, not those the
            // library has no system for.
            result.unmatchedDATs = []
            result.systemDATs = Self.isArcade(system)
                ? arcade.name(of: Self.arcadeSource(for: system)).map { [$0] } ?? arcade.names
                : verifier.sets.filter { $0.system == system }.map(\.name)
        }
        let arcadeSystems = Set(files.map(\.system).filter(Self.isArcade))
        result.missingArcadeDATs = ArcadeVerifier.Source.allCases.filter { source in
            !arcade.sources.contains(source) && arcadeSystems.contains { Self.arcadeSource(for: $0) == source }
        }
        for source in ArcadeVerifier.Source.allCases where arcadeSystems.contains(where: { Self.arcadeSource(for: $0) == source }) {
            result.arcadeDATs[source] = arcade.name(of: source)
        }
        report = .verify(result)
    }

    /// Checks one game again, for what's wrong with it, and saves what's
    /// found: quicker than verifying its whole system.
    func recheck(_ game: Game, datsFolder: URL, scanCoordinator: ScanCoordinator) async -> DATVerifier.Check? {
        let url = game.romAbsoluteURL
        let system = CanonicalSystemID(game.systemCanonicalID)
        let biosDirectory = datsFolder.deletingLastPathComponent().appending(path: "BIOS", directoryHint: .isDirectory)
        let check = await Task.detached(priority: .userInitiated) { () -> DATVerifier.Check? in
            if Self.isArcade(system) {
                let arcade = ArcadeVerifier.load(from: datsFolder, wanted: [url.deletingPathExtension().lastPathComponent], cacheDirectory: Self.arcadeCache)
                return arcade.check(url, preferring: Self.arcadeSource(for: system), biosDirectory: biosDirectory)
            }
            return DATVerifier.load(from: datsFolder).check(url, system: system)
        }.value
        if let check {
            await scanCoordinator.saveDATVerdicts([game.romAbsolutePath: (check.verdict.rawValue, check.name, check.detail)])
        }
        return check
    }

    /// Downloads an arcade DAT into the DATs folder, from FinalBurn Neo's
    /// repository or MAME's latest release, then checks again.
    func downloadArcadeDAT(_ source: ArcadeVerifier.Source, datsFolder: URL, scanCoordinator: ScanCoordinator, system: CanonicalSystemID?) async {
        guard !isBusy else { return }
        activity = Activity(title: source == .fbneo
                            ? String(localized: "Downloading FinalBurn Neo's DAT…")
                            : String(localized: "Downloading MAME's game list…"))
        let saved: Bool
        do {
            try FileManager.default.createDirectory(at: datsFolder, withIntermediateDirectories: true)
            switch source {
            case .fbneo:
                let (data, response) = try await URLSession.shared.data(from: ArcadeNameIndex.datURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try data.write(to: datsFolder.appending(path: "FinalBurn Neo (Arcade only).dat"), options: .atomic)
            case .mame:
                // The newest release's -listxml, as MAME publishes it.
                let latest = URL(string: "https://api.github.com/repos/mamedev/mame/releases/latest")!
                let (json, _) = try await URLSession.shared.data(from: latest)
                struct Release: Decodable {
                    struct Asset: Decodable { let name: String; let browser_download_url: URL }
                    let assets: [Asset]
                }
                guard let asset = try JSONDecoder().decode(Release.self, from: json).assets.first(where: { ArcadeVerifier.isArcadeZip(URL(fileURLWithPath: $0.name)) }) else {
                    throw URLError(.resourceUnavailable)
                }
                let (file, response) = try await URLSession.shared.download(from: asset.browser_download_url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let target = datsFolder.appending(path: asset.name)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: file, to: target)
                // An older version's list goes, so it isn't read instead.
                let older = ((try? FileManager.default.contentsOfDirectory(at: datsFolder, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent != asset.name && ArcadeVerifier.isArcadeZip($0) }
                for file in older { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
            }
            saved = true
        } catch {
            saved = false
        }
        activity = nil
        guard saved else {
            outcome = Outcome(title: String(localized: "Verify Games"), message: String(localized: "The DAT couldn't be downloaded. Check the connection and try again."))
            return
        }
        await verify(datsFolder: datsFolder, scanCoordinator: scanCoordinator, from: reportHost, system: system)
    }

    /// Gives the games No-Intro's names for them, with what's named
    /// after them, then checks again.
    func rename(_ games: [VerifyReport.Game], emulationFolder: EmulationFolder, romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        guard !isBusy, !games.isEmpty else { return }
        activity = Activity(title: String(localized: "Renaming games…"), fraction: 0)
        let jobs = games.compactMap { game -> (URL, String, URL, [URL], GameToRemove, CanonicalSystemID)? in
            guard let name = game.datName, game.path.hasSuffix(game.relativePath) else { return nil }
            let systemFolder = URL(fileURLWithPath: String(game.path.dropLast(game.relativePath.count)), isDirectory: true)
            let file = URL(fileURLWithPath: game.path)
            return (file, name, systemFolder, [emulationFolder.saves(for: game.system), emulationFolder.states(for: game.system)],
                    GameToRemove(rom: file, systemFolder: systemFolder, relativePath: game.relativePath), game.system)
        }
        let (renamed, duplicates) = await Task.detached(priority: .userInitiated) { () -> ([LibraryStore.RenamedFile], Int) in
            var renamed: [LibraryStore.RenamedFile] = []
            var duplicates = 0
            for (file, name, systemFolder, saveFolders, game, system) in jobs {
                if let moved = GameRenaming.rename(file, to: name, systemFolder: systemFolder, saveFolders: saveFolders) {
                    renamed.append(LibraryStore.RenamedFile(from: moved.from.path, to: moved.to.path, media: moved.media))
                    continue
                }
                // The name's taken by the very same dump: this copy goes
                // to the Trash, its media with it.
                let existing = file.deletingLastPathComponent()
                    .appending(path: file.pathExtension.isEmpty ? GameRenaming.fileStem(name) : "\(GameRenaming.fileStem(name)).\(file.pathExtension)")
                if existing.standardizedFileURL != file.standardizedFileURL,
                   FileManager.default.fileExists(atPath: existing.path),
                   DATVerifier.sameDump(file, existing, system: system),
                   Self.trash(game) != nil {
                    duplicates += 1
                }
            }
            return (renamed, duplicates)
        }.value
        await scanCoordinator.applyRenames(renamed)
        await scanCoordinator.scan(romsRootURLs: romsRoots)
        activity = nil
        let kept = games.count - renamed.count - duplicates
        var lines = [String(localized: "\(renamed.count) games renamed, with their media, gamelist entries and saves.")]
        if duplicates > 0 {
            lines.append(String(localized: "\(duplicates) duplicates moved to the Trash: a file with the right name already held the same dump."))
        }
        if kept > 0 {
            lines.append(String(localized: "\(kept) kept their names: another file already has the new one, with other data."))
        }
        outcome = Outcome(title: String(localized: "Rename Games"), message: lines.joined(separator: " "))
    }

    private static func report(files: [LibraryStore.GameFile], checks: [String: DATVerifier.Check?], verifier: DATVerifier) -> VerifyReport {
        var report = VerifyReport()
        report.datCount = verifier.sets.count
        report.unmatchedDATs = verifier.sets.filter { $0.system == nil }.map(\.name)
        var systems: [CanonicalSystemID: VerifyReport.System] = [:]
        var withoutDAT: [CanonicalSystemID: Int] = [:]
        func name(_ id: CanonicalSystemID) -> String { SystemTaxonomy.definition(for: id)?.displayName ?? id.rawValue }
        for file in files {
            guard let check = checks[file.path] else {
                // Not what No-Intro catalogues: arcade romsets, hacks,
                // discs (Redump's).
                if ROMHacks.base(of: file.system) == nil, isArcade(file.system) || DATVerifier.canCheck(URL(fileURLWithPath: file.path)) {
                    withoutDAT[file.system, default: 0] += 1
                }
                continue
            }
            var system = systems[file.system] ?? VerifyReport.System(id: file.system, name: name(file.system))
            let game = VerifyReport.Game(path: file.path, relativePath: file.relativePath, system: file.system, title: file.title, datName: check?.name, detail: check?.detail)
            switch check?.verdict {
            case .verified?:
                system.verified += 1
                system.verifiedGames.append(game)
                // An arcade set keeps its set name: no renaming.
                let stem = URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
                if !isArcade(file.system), stem != check?.name { system.renamed.append(game) }
            case .differs?: system.differs.append(game)
            case .unknown?: system.unknown.append(game)
            case .incomplete?: system.incomplete.append(game)
            case nil: system.skipped += 1
            }
            systems[file.system] = system
        }
        report.systems = systems.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        report.withoutDAT = withoutDAT.map { (name($0.key), $0.value) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return report
    }

    // MARK: - One game

    /// What the selected game's files can become.
    enum GameConversion {
        case discs([CHDConversion.Candidate])
        case cartridge(URL)
        case back([URL])

        var isDiscs: Bool {
            if case .discs = self { true } else { false }
        }
    }

    func compression(for game: Game) -> GameConversion? {
        let url = game.romAbsoluteURL
        let system = CanonicalSystemID(game.systemCanonicalID)
        let discs = CHDConversion.candidates(forGame: url, system: system)
        if !discs.isEmpty { return .discs(discs) }
        return ROMZipping.canZip(url, system: system) ? .cartridge(url) : nil
    }

    func conversionBack(for game: Game) -> GameConversion? {
        let chds = CHDConversion.chds(forGame: game.romAbsoluteURL)
        return chds.isEmpty ? nil : .back(chds)
    }

    func run(_ conversion: GameConversion, title: String, romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        guard !isBusy else { return }
        reportHost = .library
        let chdman = chdman
        switch conversion {
        case .discs, .back: guard chdman != nil else { return }
        case .cartridge: break
        }
        activity = Activity(title: String(localized: "Converting \(title)…"))
        let result = await Task.detached(priority: .userInitiated) { () -> GameCompressionPlan.Result in
            switch conversion {
            case .discs(let discs):
                return GameCompressionPlan.apply(GameCompressionPlan(discs: discs), chdman: chdman)
            case .cartridge(let rom):
                return GameCompressionPlan.apply(GameCompressionPlan(cartridges: [rom]), chdman: chdman)
            case .back(let chds):
                var result = GameCompressionPlan.Result()
                for chd in chds {
                    if let chdman, CHDConversion.extract(chd, chdman: chdman) { result.compressed += 1 } else { result.failed += 1 }
                }
                return result
            }
        }.value
        await scanCoordinator.scan(romsRootURLs: romsRoots)
        activity = nil
        if result.failed > 0 {
            outcome = Outcome(title: title, message: String(localized: "chdman couldn't convert \(title). Its files haven't changed."))
        } else if result.compressed == 0, case .cartridge = conversion {
            outcome = Outcome(title: title, message: String(localized: "\(title) doesn't get smaller zipped, so it stays as it is."))
        }
    }

    // MARK: - chdman

    /// Homebrew, which can install `chdman` (its rom-tools package is built
    /// from MAME's own source).
    static var brew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func refreshCHDMan() {
        chdman = CHDConversion.findCHDMan()
    }

    func installCHDMan() async {
        guard let brew = Self.brew, !isInstallingCHDMan else { return }
        isInstallingCHDMan = true
        chdmanError = nil
        let ok = await Task.detached { () -> Bool in
            let process = Process()
            process.executableURL = brew
            process.arguments = ["install", "rom-tools"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
        isInstallingCHDMan = false
        refreshCHDMan()
        if !ok || chdman == nil {
            chdmanError = String(localized: "Homebrew couldn't install rom-tools. Try “brew install rom-tools” in Terminal.")
        }
    }

    // MARK: - Backups

    static let backupFolderKey = "backupFolder"
    static let backsUpWeeklyKey = "backsUpWeekly"
    static let lastBackupKey = "lastBackupDate"

    static var backupFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: backupFolderKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var lastBackup: Date? {
        UserDefaults.standard.object(forKey: lastBackupKey) as? Date
    }

    /// Asks where backups go; nil if cancelled.
    @discardableResult
    func chooseBackupFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where Attic keeps backups of your saves. Another drive or a synced folder keeps them safest.")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: Self.backupFolderKey)
        return url
    }

    /// Zips saves, states, collections and gamelists into the backup
    /// folder (asking for one first if there's none). `quietly`, for the
    /// weekly backup: no questions, and only a failure is told.
    func backUp(emulationRoot: URL, quietly: Bool = false, from host: Host = .library) async {
        guard !isBusy else { return }
        guard let folder = Self.backupFolder ?? (quietly ? nil : chooseBackupFolder()) else { return }
        // A drive or share that isn't there now: next time.
        if quietly, !FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path) { return }
        reportHost = host
        activity = Activity(title: String(localized: "Backing up saves…"))
        let result = await Task.detached(priority: .utility) { () -> Result<URL, Error> in
            Result { try SaveBackup.create(from: emulationRoot, to: folder) }
        }.value
        activity = nil
        switch result {
        case .success(let zip):
            UserDefaults.standard.set(Date(), forKey: Self.lastBackupKey)
            if !quietly {
                let size = ByteCountFormatter.string(fromByteCount: MediaFolder.fileSize(zip), countStyle: .file)
                outcome = Outcome(title: String(localized: "Saves Backed Up"),
                                  message: String(localized: "\(zip.lastPathComponent), \(size), in \(folder.path). The newest \(SaveBackup.keptCount) backups are kept."))
            }
        case .failure:
            outcome = Outcome(title: String(localized: "Backup Failed"),
                              message: String(localized: "Attic couldn't write a backup to \(folder.path). Check that the folder is there and has room."))
        }
    }

    /// The weekly backup, when it's on and due.
    func backUpIfDue(emulationRoot: URL) async {
        guard UserDefaults.standard.bool(forKey: Self.backsUpWeeklyKey), Self.backupFolder != nil,
              SaveBackup.isDue(lastBackup: Self.lastBackup) else { return }
        await backUp(emulationRoot: emulationRoot, quietly: true)
    }

    // MARK: - Unzipped games

    /// What zipped games take up once unzipped to be played.
    var unzippedGamesBytes: Int64 {
        let folder = ZippedROMExtractor.defaultCacheDirectory
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []
        return files.reduce(0) { $0 + MediaFolder.fileSize($1) }
    }

    /// Removes the unzipped copies; a game unzips again when next played.
    func emptyUnzippedGames() {
        try? FileManager.default.removeItem(at: ZippedROMExtractor.defaultCacheDirectory)
    }

    // MARK: - Text

    private static func summary(of result: GameCompressionPlan.Result) -> String {
        let saved = ByteCountFormatter.string(fromByteCount: max(result.savedBytes, 0), countStyle: .file)
        if result.failed > 0 {
            return String(localized: "\(result.compressed) games compressed, \(saved) saved. \(result.failed) couldn't be converted and haven't changed.")
        }
        return String(localized: "\(result.compressed) games compressed, \(saved) saved.")
    }
}
