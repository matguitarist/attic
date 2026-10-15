import Foundation
import Observation
import AppKit
import AtticModels
import AtticLibraryScanning
import AtticEmulation

/// Files games dropped on the library window into the right ROMs folder,
/// with the media and gamelist that came with them.
///
/// Each game's system is, in order: the sidebar system it's dropped on;
/// the system a dropped folder is named after (`atari2600`, or each
/// system folder of a whole `roms` folder); the system shown, when it
/// takes the file; else the one its file type says, asking when that
/// could be several. Files on the same disk are moved, others copied —
/// in the background, with `progress` for the status bar.
@Observable
@MainActor
final class ROMImportCoordinator {
    /// Files whose system Attic has to ask about.
    struct Question: Identifiable {
        let id = UUID()
        let files: [URL]
        let choices: [CanonicalSystemID]
    }

    enum Progress: Equatable {
        /// Going through dropped folders.
        case looking
        /// Moving or copying game `done + 1` of `total`.
        case adding(done: Int, total: Int, name: String)
        /// Vita3K installing a game or its firmware.
        case installingInVita3K(name: String)
    }

    /// One game's files (a .cue first, then its tracks), the system the
    /// folder it came from is named after, and its file type.
    struct Game: Sendable {
        let files: [URL]
        let folderSystem: CanonicalSystemID?
        let fileExtension: String
        /// What it's called once filed, when not its own name: a dumped PS4
        /// folder (CUSA00900) becomes "Bloodborne.ps4".
        var destinationName: String? = nil
    }

    /// What placing one game did.
    struct Placed: Sendable {
        var added = false
        var alreadyThere = false
        var media = 0
    }

    private(set) var question: Question?
    private(set) var progress: Progress?
    /// The summary shown once everything's placed.
    var summary: String?

    private var queue: [Question] = []
    private var romsRoots: [URL] = []
    private var added: [CanonicalSystemID: Int] = [:]
    private var mediaAdded = 0
    /// Arcade BIOS sets, which go beside the games but aren't games.
    private var biosSets: [String] = []
    private var alreadyThere = 0
    private var notGames = 0
    private var unknown: [String] = []
    private var vitaItems: [URL] = []
    private var sentToVita3K = 0
    private var vita3KMissing = false
    private var vita3KFailed: [String] = []
    private var emulationFolder: EmulationFolder?
    /// Where each source folder's games went, for its gamelist.
    private var destinations: [URL: [CanonicalSystemID: Int]] = [:]
    private var finish: () -> Void = {}

    var isBusy: Bool { progress != nil || question != nil }

    func receive(_ urls: [URL], into system: CanonicalSystemID? = nil, shown: CanonicalSystemID? = nil,
                 romsRoots: [URL], emulationFolder: EmulationFolder, then finish: @escaping () -> Void) {
        guard !romsRoots.isEmpty, !urls.isEmpty, !isBusy else { return }
        self.romsRoots = romsRoots
        self.emulationFolder = emulationFolder
        sentToVita3K = 0
        vita3KMissing = false
        vita3KFailed = []
        self.finish = finish
        added = [:]
        mediaAdded = 0
        biosSets = []
        alreadyThere = 0
        notGames = 0
        unknown = []
        destinations = [:]
        progress = .looking

        Task {
            let (games, skipped, vita) = await Task.detached(priority: .userInitiated) { Self.games(in: urls, picturesAreGames: system?.baseSystem == .pico8) }.value
            notGames = skipped
            vitaItems = vita

            var placements: [(files: [URL], system: CanonicalSystemID, name: String?)] = []
            var asking: [[CanonicalSystemID]: [URL]] = [:]
            for game in games {
                if let target = system ?? game.folderSystem {
                    placements.append((game.files, target, game.destinationName))
                } else if let shown, SystemROMExtensions.extensions(for: shown)?.contains(game.fileExtension) == true {
                    placements.append((game.files, shown, nil))
                } else {
                    let choices = ROMImport.systems(forExtension: game.fileExtension)
                    switch choices.count {
                    case 0: unknown.append(game.files[0].lastPathComponent)
                    case 1: placements.append((game.files, choices[0], nil))
                    default: asking[choices, default: []] += game.files
                    }
                }
            }
            queue = asking.map { Question(files: $0.value, choices: $0.key) }
                .sorted { $0.files[0].lastPathComponent < $1.files[0].lastPathComponent }
            await place(placements)
            next()
        }
    }

    func answer(_ system: CanonicalSystemID?) {
        guard let question else { return }
        self.question = nil
        if let system {
            Task {
                await place(Self.groups(question.files).map { ($0, system, nil) })
                next()
            }
        } else {
            unknown += question.files.map(\.lastPathComponent)
            next()
        }
    }

    private func next() {
        if !queue.isEmpty {
            progress = nil
            question = queue.removeFirst()
            return
        }
        Task {
            let sources = destinations
            let roots = romsRoots
            await Task.detached(priority: .userInitiated) { Self.importGamelists(sources, romsRoots: roots) }.value
            await installVitaItems()
            progress = nil
            summary = makeSummary()
            if !added.isEmpty || sentToVita3K > 0 { finish() }
        }
    }

    /// One game at a time in the background, so the window stays live and
    /// the status bar can count.
    private func place(_ placements: [(files: [URL], system: CanonicalSystemID, name: String?)]) async {
        let roots = romsRoots
        for (index, placement) in placements.enumerated() {
            progress = .adding(done: index, total: placements.count, name: placement.name ?? placement.files[0].lastPathComponent)
            let result = await Task.detached(priority: .userInitiated) {
                Self.place(placement.files, in: placement.system, romsRoots: roots, as: placement.name)
            }.value
            let name = placement.name ?? placement.files[0].lastPathComponent
            if result.added, ArcadeBIOSSets.isBIOSSet(name, system: placement.system) {
                biosSets.append(name)
            } else if result.added {
                added[placement.system, default: 0] += 1
                destinations[placement.files[0].deletingLastPathComponent(), default: [:]][placement.system, default: 0] += 1
            }
            if result.alreadyThere { alreadyThere += 1 }
            mediaAdded += result.media
        }
    }

    /// Hands Vita games, packages and firmware to Vita3K one at a time.
    /// A game starts once installed (that's how Vita3K installs them), so
    /// this waits for it to be closed; Attic then lists what's installed.
    private func installVitaItems() async {
        guard !vitaItems.isEmpty, let emulationFolder else { return }
        let installer = EmulatorInstaller(paths: emulationFolder.installerPaths)
        guard let app = installer.installedAppURL(for: EmulatorCatalog.vita3K) else {
            vita3KMissing = true
            unknown += vitaItems.map(\.lastPathComponent)
            return
        }
        let executable = app.appending(path: EmulatorCatalog.vita3K.executableRelativePath)
        if let root = romsRoots.first {
            try? FileManager.default.createDirectory(at: root.appending(path: "psvita"), withIntermediateDirectories: true)
        }
        for item in vitaItems {
            var arguments: [String]
            switch item.pathExtension.lowercased() {
            case "pup":
                arguments = ["--firmware", item.path]
            case "pkg":
                guard let zRIF = Self.askForZRIF(item) else { unknown.append(item.lastPathComponent); continue }
                arguments = ["--pkg", item.path, "--zrif", zRIF]
            default:
                arguments = [item.path]
            }
            progress = .installingInVita3K(name: item.lastPathComponent)
            let installed = await Task.detached(priority: .userInitiated) { () -> Bool in
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                guard (try? process.run()) != nil else { return false }
                process.waitUntilExit()
                return process.terminationReason == .exit && process.terminationStatus == 0
            }.value
            if installed { sentToVita3K += 1 } else { vita3KFailed.append(item.lastPathComponent) }
        }
        let roots = romsRoots
        _ = await Task.detached { Vita3KLibrary.addShortcuts(romsRoots: roots) }.value
    }

    /// A PS Vita .pkg is encrypted; its zRIF (from the license that came
    /// with it, as NoPayStation lists them) unlocks it.
    private static func askForZRIF(_ package: URL) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "License for “\(package.lastPathComponent)”")
        alert.informativeText = String(localized: "A PS Vita .pkg needs its zRIF license key to be installed. Paste it here.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "KO5ifR1dQ+eHBlbn…"
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Install"))
        alert.addButton(withTitle: String(localized: "Skip"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private func makeSummary() -> String? {
        var parts: [String] = []
        if sentToVita3K > 0 {
            parts.append(String(localized: "\(sentToVita3K) installed in Vita3K; its games are now in PS Vita."))
        }
        if !vita3KFailed.isEmpty {
            parts.append(String(localized: "Vita3K couldn't install \(vita3KFailed.formatted(.list(type: .and)))."))
        }
        if vita3KMissing {
            parts.append(String(localized: "PS Vita games and firmware need Vita3K: install it in Settings › Emulators, then add them again."))
        }
        if !added.isEmpty {
            let systems = added.sorted { $0.value > $1.value }.map { system, count in
                "\(SystemTaxonomy.definition(for: system)?.displayName ?? system.rawValue) (\(count))"
            }
            parts.append(String(localized: "Added to \(systems.formatted(.list(type: .and)))."))
        }
        if !biosSets.isEmpty {
            parts.append(String(localized: "BIOS sets put beside the games, which can now start: \(biosSets.formatted(.list(type: .and)))."))
        }
        if mediaAdded > 0 {
            parts.append(String(localized: "\(mediaAdded) covers, videos and manuals came along."))
        }
        if alreadyThere > 0 {
            parts.append(String(localized: "\(alreadyThere) were already in your ROMs folder."))
        }
        if notGames > 0 {
            parts.append(String(localized: "\(notGames) files that aren't games for their system were left where they are."))
        }
        if !unknown.isEmpty {
            parts.append(String(localized: "Not added, no system takes them: \(unknown.prefix(5).formatted(.list(type: .and)))."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

// MARK: - File work (off the main actor)

extension ROMImportCoordinator {
    /// Disc images that name other files, which go along with them.
    nonisolated private static let leadExtensions: Set<String> = ["cue", "gdi", "ccd", "m3u", "toc"]

    /// Other apps' notes and lists that sit among games.
    nonisolated private static func isClutter(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix("gamelist") && name.hasSuffix(".xml")
            || ["_sysinfo.txt", "systeminfo.txt", "_info.txt", "readme.txt", "systems.txt"].contains(name)
    }

    /// The games in what was dropped, and how many files in system
    /// folders weren't games for that system.
    /// PICO-8 cartridges are PNG pictures (`game.p8.png`); any other
    /// picture dropped on its own is someone's cover or logo dropped in
    /// the wrong place, not a game — unless dropped on PICO-8 itself.
    nonisolated static func isPicture(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tif", "tiff"].contains(url.pathExtension.lowercased())
            && !name.hasSuffix(".p8.png")
    }

    nonisolated static func games(in urls: [URL], picturesAreGames: Bool = false) -> (games: [Game], notGames: Int, vita: [URL]) {
        var loose: [URL] = []
        var games: [Game] = []
        var notGames = 0
        var vita: [URL] = []
        for url in urls {
            if let console = consoleGame(url, vita: &vita) {
                games.append(console)
            } else if isDirectory(url), vita.last == url {
                continue
            } else if isDirectory(url), !SystemROMExtensions.gameFolderExtensions.contains(url.pathExtension.lowercased()) {
                games += self.games(inFolder: url, system: SystemTaxonomy.system(forShortName: url.lastPathComponent.lowercased())?.canonicalID, notGames: &notGames, vita: &vita)
            } else if isForVita3K(url) {
                vita.append(url)
            } else if !picturesAreGames, isPicture(url) {
                notGames += 1
            } else if !isClutter(url) {
                loose.append(url)
            }
        }
        return (games + groups(loose).map { game($0, system: nil) }, notGames, vita)
    }

    /// A .vpk, Vita firmware, or a PS Vita (not PS3 or PS4) package.
    nonisolated private static func isForVita3K(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "vpk": true
        case "pup": url.lastPathComponent.uppercased().hasPrefix("PSV")
        case "pkg": Vita3KLibrary.isVitaPackage(url)
        default: false
        }
    }

    /// A dumped PS4 game folder, filed as "<Title>.ps4"; a dumped Vita
    /// game folder goes to `vita`, for Vita3K to install.
    nonisolated private static func consoleGame(_ url: URL, vita: inout [URL]) -> Game? {
        guard isDirectory(url), let found = Vita3KLibrary.consoleGame(in: url) else { return nil }
        guard found.system == .ps4 else {
            vita.append(url)
            return nil
        }
        let name = CollectionFile.folderName(for: found.title)
        return Game(files: [url], folderSystem: .ps4, fileExtension: "ps4", destinationName: "\(name).ps4")
    }

    /// A dropped folder's games: its own files, game folders (Game.ps3),
    /// and what's in its other folders — a system folder inside (a whole
    /// `roms` folder) going to that system. Media folders are left for
    /// the games' media.
    nonisolated private static func games(inFolder folder: URL, system: CanonicalSystemID?, notGames: inout Int, vita: inout [URL],
                                          skipping listed: Set<URL> = []) -> [Game] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        var files: [URL] = []
        var games: [Game] = []
        // A playlist and its discs are one game, wherever they are beside
        // it (RetroBat keeps them in a MultiDisc folder).
        var listed = listed
        for playlist in entries where playlist.pathExtension.lowercased() == "m3u" && !listed.contains(playlist.standardizedFileURL) {
            let parts = FrontEndMedia.files(ofGame: playlist)
            guard parts.count > 1, system.map({ SystemROMExtensions.accepts(playlist.lastPathComponent, for: $0) }) ?? true else { continue }
            listed.formUnion(parts.map(\.standardizedFileURL))
            games.append(game(parts, system: system))
        }
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !listed.contains(entry.standardizedFileURL) {
            let name = entry.lastPathComponent.lowercased()
            if let console = consoleGame(entry, vita: &vita) {
                games.append(console)
            } else if isDirectory(entry), vita.last == entry {
                continue
            } else if isDirectory(entry) {
                if SystemROMExtensions.gameFolderExtensions.contains(entry.pathExtension.lowercased()) {
                    games.append(game([entry], system: system))
                } else if !ImportedMedia.nonGameFolderNames.contains(name) {
                    let inner = SystemTaxonomy.system(forShortName: name)?.canonicalID ?? system
                    games += self.games(inFolder: entry, system: inner, notGames: &notGames, vita: &vita, skipping: listed)
                }
            } else if isForVita3K(entry) {
                vita.append(entry)
            } else if isClutter(entry) || ImportedMedia.isMedia(entry, for: system) {
                // Other apps' files, or a game's cover or video, which
                // comes along with the game.
                continue
            } else if let system, !SystemROMExtensions.accepts(entry.lastPathComponent, for: system) {
                notGames += 1
            } else {
                files.append(entry)
            }
        }
        return groups(files).map { game($0, system: system) } + games
    }

    nonisolated private static func game(_ files: [URL], system: CanonicalSystemID?) -> Game {
        // A known system doesn't need the zip looked into.
        Game(files: files, folderSystem: system, fileExtension: system == nil ? effectiveExtension(files[0]) : files[0].pathExtension.lowercased())
    }

    nonisolated static func place(_ files: [URL], in system: CanonicalSystemID, romsRoots: [URL], as name: String? = nil) -> Placed {
        var result = Placed()
        guard let folder = ROMImport.folder(for: system, romsRoots: romsRoots) else { return result }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let lead = files[0]
        // Looked up before the game moves away from its media.
        let media = ImportedMedia.media(forROM: lead, system: system)
        for (index, file) in files.enumerated() {
            // The rest keep their place beside the lead: a playlist's discs
            // in their MultiDisc folder.
            let destination = folder.appending(path: index == 0 ? (name ?? file.lastPathComponent)
                                                   : DiscPlaylists.relativePath(of: file, in: lead.deletingLastPathComponent()))
            guard !fileManager.fileExists(atPath: destination.path) else {
                if index == 0 { result.alreadyThere = true }
                continue
            }
            try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if transfer(file, to: destination), index == 0 {
                result.added = true
                // A playlist made on Windows, made for here.
                if destination.pathExtension.lowercased() == "m3u", let text = try? String(contentsOf: destination, encoding: .utf8),
                   let mac = DiscPlaylists.macText(of: text) {
                    try? mac.write(to: destination, atomically: true, encoding: .utf8)
                }
            }
        }
        for (file, kind) in media {
            let base = MediaFolder.baseURL(forSystemFolder: folder, romRelativePath: lead.lastPathComponent, kind: kind)
            guard MediaFolder.existingFiles(base: base).isEmpty, !fileManager.fileExists(atPath: base.appendingPathExtension("pdf").path) else { continue }
            try? fileManager.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            if transfer(file, to: base.appendingPathExtension(file.pathExtension.lowercased())) { result.media += 1 }
        }
        return result
    }

    /// Each source folder's gamelist, into the gamelist of the system most
    /// of its games went to.
    nonisolated private static func importGamelists(_ destinations: [URL: [CanonicalSystemID: Int]], romsRoots: [URL]) {
        for (source, systems) in destinations {
            guard let system = systems.max(by: { $0.value < $1.value })?.key,
                  let gamelist = ImportedMedia.gamelist(near: source),
                  let incoming = try? String(contentsOf: gamelist, encoding: .utf8),
                  let folder = ROMImport.folder(for: system, romsRoots: romsRoots) else { continue }
            let destination = folder.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: EmulationLayout.gamelists).appending(path: folder.lastPathComponent).appending(path: "gamelist.xml")
            let existing = try? String(contentsOf: destination, encoding: .utf8)
            let merged = ImportedMedia.mergedGamelist(incoming, into: existing, systemFolder: folder)
            guard merged != existing else { continue }
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? merged.write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    /// Each game's files together: a .cue with the .bin files named like
    /// it, and so on. The lead file comes first.
    nonisolated static func groups(_ urls: [URL]) -> [[URL]] {
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Playlists first: they take their discs' sheets along.
        let leads = sorted.filter { leadExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { ($0.pathExtension.lowercased() == "m3u" ? 0 : 1) < ($1.pathExtension.lowercased() == "m3u" ? 0 : 1) }
        var taken = Set<URL>()
        var groups: [[URL]] = []
        for lead in leads where !taken.contains(lead) {
            let stem = lead.deletingPathExtension().lastPathComponent
            var companions = sorted.filter { $0 != lead && !taken.contains($0) && !leads.contains($0) && $0.lastPathComponent.hasPrefix(stem) }
            // A playlist's discs, dropped with it or not.
            if lead.pathExtension.lowercased() == "m3u" {
                companions += FrontEndMedia.files(ofGame: lead).dropFirst().filter { !companions.contains($0) }
            }
            taken.formUnion(companions + [lead])
            groups.append([lead] + companions)
        }
        return groups + sorted.filter { !taken.contains($0) }.map { [$0] }
    }

    /// A zip holding a single kind of file goes by that file's type
    /// (Game.zip with Game.sfc is a SNES game); anything else by its own.
    nonisolated static func effectiveExtension(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard ext == "zip" else { return ext }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return ext }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        let inner = Set(output.split(separator: "\n").filter { !$0.hasSuffix("/") }.map { ($0 as NSString).pathExtension.lowercased() })
        return inner.count == 1 ? inner.first! : ext
    }

    /// Moves on the same disk, copies from another.
    nonisolated private static func transfer(_ file: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        if sameVolume(file, destination.deletingLastPathComponent()), (try? fileManager.moveItem(at: file, to: destination)) != nil {
            return true
        }
        return (try? fileManager.copyItem(at: file, to: destination)) != nil
    }

    nonisolated private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let first = try? a.resourceValues(forKeys: key).volumeIdentifier as? NSObject,
              let second = try? b.resourceValues(forKeys: key).volumeIdentifier as? NSObject else { return false }
        return first.isEqual(second)
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
