import Foundation
import Observation
import AtticModels
import AtticLibraryScanning

/// Files games dropped on the library window into the right ROMs folder,
/// with the media and gamelist that came with them.
///
/// Each game's system is, in order: the sidebar system it's dropped on;
/// the system a dropped folder is named after (`atari2600`, or each
/// system folder of a whole `roms` folder); the system shown, when it
/// takes the file; else the one its file type says, asking when that
/// could be several. Files on the same disk are moved, others copied.
@Observable
@MainActor
final class ROMImportCoordinator {
    /// Files whose system Attic has to ask about.
    struct Question: Identifiable {
        let id = UUID()
        let files: [URL]
        let choices: [CanonicalSystemID]
    }

    /// One game's files (a .cue first, then its tracks), and the system
    /// the folder it came from is named after.
    private struct Game {
        let files: [URL]
        let folderSystem: CanonicalSystemID?
    }

    private(set) var question: Question?
    /// The summary shown once everything's placed.
    var summary: String?

    private var queue: [Question] = []
    private var romsRoots: [URL] = []
    private var added: [CanonicalSystemID: Int] = [:]
    private var mediaAdded = 0
    private var alreadyThere = 0
    private var notGames = 0
    private var unknown: [String] = []
    /// Where each source folder's games went, for its gamelist.
    private var destinations: [URL: [CanonicalSystemID: Int]] = [:]
    private var finish: () -> Void = {}

    /// Disc images that name other files, which go along with them.
    private static let leadExtensions: Set<String> = ["cue", "gdi", "ccd", "m3u", "toc"]
    /// Other apps' notes and lists that sit among games.
    private static func isClutter(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasPrefix("gamelist") && name.hasSuffix(".xml")
            || ["_sysinfo.txt", "systeminfo.txt", "_info.txt", "readme.txt", "systems.txt"].contains(name)
    }

    func receive(_ urls: [URL], into system: CanonicalSystemID? = nil, shown: CanonicalSystemID? = nil,
                 romsRoots: [URL], then finish: @escaping () -> Void) {
        guard !romsRoots.isEmpty, !urls.isEmpty else { return }
        self.romsRoots = romsRoots
        self.finish = finish
        added = [:]
        mediaAdded = 0
        alreadyThere = 0
        notGames = 0
        unknown = []
        destinations = [:]

        var asking: [[CanonicalSystemID]: [URL]] = [:]
        for game in games(in: urls) {
            let lead = game.files[0]
            let ext = Self.effectiveExtension(lead)
            if let target = system ?? game.folderSystem {
                place(game.files, in: target)
            } else if let shown, SystemROMExtensions.extensions(for: shown)?.contains(ext) == true {
                place(game.files, in: shown)
            } else {
                let choices = ROMImport.systems(forExtension: ext)
                switch choices.count {
                case 0: unknown.append(lead.lastPathComponent)
                case 1: place(game.files, in: choices[0])
                default: asking[choices, default: []] += game.files
                }
            }
        }
        queue = asking.map { Question(files: $0.value, choices: $0.key) }
            .sorted { $0.files[0].lastPathComponent < $1.files[0].lastPathComponent }
        next()
    }

    func answer(_ system: CanonicalSystemID?) {
        if let system, let question {
            for group in Self.groups(question.files) { place(group, in: system) }
        } else if let question {
            unknown += question.files.map(\.lastPathComponent)
        }
        next()
    }

    private func next() {
        if queue.isEmpty {
            question = nil
            importGamelists()
            summary = makeSummary()
            if !added.isEmpty { finish() }
        } else {
            question = queue.removeFirst()
        }
    }

    // MARK: - Finding the games

    private func games(in urls: [URL]) -> [Game] {
        var loose: [URL] = []
        var games: [Game] = []
        for url in urls {
            if Self.isDirectory(url), !SystemROMExtensions.gameFolderExtensions.contains(url.pathExtension.lowercased()) {
                games += self.games(inFolder: url, system: SystemTaxonomy.system(forShortName: url.lastPathComponent.lowercased())?.canonicalID)
            } else if !Self.isClutter(url) {
                loose.append(url)
            }
        }
        return games + Self.groups(loose).map { Game(files: $0, folderSystem: nil) }
    }

    /// A dropped folder's games: its own files, game folders (Game.ps3),
    /// and what's in its other folders — a system folder inside (a whole
    /// `roms` folder) going to that system. Media folders are left for
    /// the games' media.
    private func games(inFolder folder: URL, system: CanonicalSystemID?) -> [Game] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        var files: [URL] = []
        var games: [Game] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent.lowercased()
            if Self.isDirectory(entry) {
                if SystemROMExtensions.gameFolderExtensions.contains(entry.pathExtension.lowercased()) {
                    games.append(Game(files: [entry], folderSystem: system))
                } else if !ImportedMedia.nonGameFolderNames.contains(name) {
                    let inner = SystemTaxonomy.system(forShortName: name)?.canonicalID ?? system
                    games += self.games(inFolder: entry, system: inner)
                }
            } else if Self.isClutter(entry) {
                continue
            } else if ImportedMedia.isMedia(entry, for: system) {
                // A game's cover or video; it comes along with the game.
                continue
            } else if let system, !SystemROMExtensions.accepts(entry.lastPathComponent, for: system) {
                notGames += 1
            } else {
                files.append(entry)
            }
        }
        return Self.groups(files).map { Game(files: $0, folderSystem: system) } + games
    }

    // MARK: - Placing

    private func place(_ files: [URL], in system: CanonicalSystemID) {
        guard let folder = ROMImport.folder(for: system, romsRoots: romsRoots) else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let lead = files[0]
        // Looked up before the game moves away from its media.
        let media = ImportedMedia.media(forROM: lead, system: system)
        for (index, file) in files.enumerated() {
            let destination = folder.appending(path: file.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else {
                if index == 0 { alreadyThere += 1 }
                continue
            }
            if Self.transfer(file, to: destination), index == 0 {
                added[system, default: 0] += 1
                destinations[lead.deletingLastPathComponent(), default: [:]][system, default: 0] += 1
            }
        }
        for (file, kind) in media {
            let base = MediaFolder.baseURL(forSystemFolder: folder, romRelativePath: lead.lastPathComponent, kind: kind)
            guard MediaFolder.existingFiles(base: base).isEmpty, !fileManager.fileExists(atPath: base.appendingPathExtension("pdf").path) else { continue }
            try? fileManager.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
            if Self.transfer(file, to: base.appendingPathExtension(file.pathExtension.lowercased())) { mediaAdded += 1 }
        }
    }

    /// Each source folder's gamelist, into the gamelist of the system most
    /// of its games went to.
    private func importGamelists() {
        for (source, systems) in destinations {
            guard let system = systems.max(by: { $0.value < $1.value })?.key,
                  let gamelist = ImportedMedia.gamelist(near: source),
                  let incoming = try? String(contentsOf: gamelist, encoding: .utf8),
                  let folder = ROMImport.folder(for: system, romsRoots: romsRoots) else { continue }
            let destination = folder.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "gamelists").appending(path: folder.lastPathComponent).appending(path: "gamelist.xml")
            let existing = try? String(contentsOf: destination, encoding: .utf8)
            let merged = ImportedMedia.mergedGamelist(incoming, into: existing, systemFolder: folder)
            guard merged != existing else { continue }
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? merged.write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    private func makeSummary() -> String? {
        var parts: [String] = []
        if !added.isEmpty {
            let systems = added.sorted { $0.value > $1.value }.map { system, count in
                "\(SystemTaxonomy.definition(for: system)?.displayName ?? system.rawValue) (\(count))"
            }
            parts.append(String(localized: "Added to \(systems.formatted(.list(type: .and)))."))
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

    // MARK: - Files

    /// Each game's files together: a .cue with the .bin files named like
    /// it, and so on. The lead file comes first.
    static func groups(_ urls: [URL]) -> [[URL]] {
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let leads = sorted.filter { leadExtensions.contains($0.pathExtension.lowercased()) }
        var taken = Set<URL>()
        var groups: [[URL]] = []
        for lead in leads {
            let stem = lead.deletingPathExtension().lastPathComponent
            let companions = sorted.filter { $0 != lead && !taken.contains($0) && !leads.contains($0) && $0.lastPathComponent.hasPrefix(stem) }
            taken.formUnion(companions + [lead])
            groups.append([lead] + companions)
        }
        return groups + sorted.filter { !taken.contains($0) }.map { [$0] }
    }

    /// A zip holding a single kind of file goes by that file's type
    /// (Game.zip with Game.sfc is a SNES game); anything else by its own.
    static func effectiveExtension(_ url: URL) -> String {
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
    private static func transfer(_ file: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        if sameVolume(file, destination.deletingLastPathComponent()), (try? fileManager.moveItem(at: file, to: destination)) != nil {
            return true
        }
        return (try? fileManager.copyItem(at: file, to: destination)) != nil
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let first = try? a.resourceValues(forKeys: key).volumeIdentifier as? NSObject,
              let second = try? b.resourceValues(forKeys: key).volumeIdentifier as? NSObject else { return false }
        return first.isEqual(second)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
