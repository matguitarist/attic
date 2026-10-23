import Foundation
import AtticModels

/// Mac games installed through Steam.
///
/// Steam lists each game it installed in an `appmanifest_<app ID>.acf`
/// in every library folder it knows (`libraryfolders.vdf`). This reads
/// them, keeps the games that are fully installed and have a Mac app (so
/// Proton-less Windows builds and tools like the redistributables stay
/// out), and keeps a `<Title> [<app ID>].steam` file (holding the app ID)
/// in the ROMs folder's `steam` folder for each, so they show up in the
/// library like any other game. They're played through Steam
/// (`steam://rungameid/<app ID>`), which keeps them updated and signed in.
public enum SteamLibrary {
    public struct InstalledGame: Equatable, Sendable {
        public let appID: String
        public let title: String
        /// `steamapps/common/<install dir>` in its library folder.
        public let folder: URL
    }

    /// Steam's own data folder, where its first library lives.
    public static var defaultSteamFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Steam", directoryHint: .isDirectory)
    }

    public static let shortcutExtension = "steam"

    /// Steam's library folders: its own, and any added on other drives.
    /// Those on drives that aren't connected are left out.
    public static func libraryFolders(steamFolder: URL = defaultSteamFolder) -> [URL] {
        var folders = [steamFolder]
        for library in libraries(steamFolder: steamFolder) where !folders.contains(where: { $0.standardizedFileURL == library.folder.standardizedFileURL }) {
            folders.append(library.folder)
        }
        return folders.filter { FileManager.default.fileExists(atPath: $0.appending(path: "steamapps").path) }
    }

    /// Every fully installed game with a Mac app, by title.
    public static func installedGames(steamFolder: URL = defaultSteamFolder) -> [InstalledGame] {
        var seen = Set<String>()
        var games: [InstalledGame] = []
        for library in libraryFolders(steamFolder: steamFolder) {
            let steamapps = library.appending(path: "steamapps", directoryHint: .isDirectory)
            let manifests = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
            for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                guard let text = try? String(contentsOf: manifest, encoding: .utf8),
                      let game = installedGame(manifest: text, steamapps: steamapps),
                      !seen.contains(game.appID), hasMacApp(game.folder) else { continue }
                seen.insert(game.appID)
                games.append(game)
            }
        }
        return games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The game an app manifest describes, when Steam finished installing
    /// it (StateFlags has bit 4, "fully installed"; others mean it's still
    /// downloading or was uninstalled).
    static func installedGame(manifest: String, steamapps: URL) -> InstalledGame? {
        guard let state = VDF.parse(manifest)["AppState"],
              let appID = state["appid"]?.string, !appID.isEmpty,
              let installDir = state["installdir"]?.string, !installDir.isEmpty,
              let flags = state["StateFlags"]?.string.flatMap(Int.init), flags & 4 != 0 else { return nil }
        let title = state["name"]?.string ?? installDir
        let folder = steamapps.appending(path: "common", directoryHint: .isDirectory)
            .appending(path: installDir, directoryHint: .isDirectory)
        return InstalledGame(appID: appID, title: title, folder: folder)
    }

    /// Whether an install folder holds a Mac app, near the top, or is one
    /// (Stardew Valley's holds `Contents` itself): Steam on a Mac installs
    /// Windows builds too, which only run through other tools.
    static func hasMacApp(_ folder: URL) -> Bool {
        if FileManager.default.fileExists(atPath: folder.appending(path: "Contents/MacOS").path) { return true }
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" { return true }
            if enumerator.level >= 3 { enumerator.skipDescendants() }
        }
        return false
    }

    /// The app ID a `.steam` file names: its contents, else the `[<ID>]` in
    /// its name.
    public static func appID(shortcut: URL) -> String? {
        if let text = try? String(contentsOf: shortcut, encoding: .utf8) {
            let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, id.allSatisfy(\.isNumber) { return id }
        }
        return shortcut.deletingPathExtension().lastPathComponent
            .firstMatch(of: /\[(\d+)\]$/).map { String($0.1) }
    }

    /// The installed game a `.steam` file names, if it's still installed.
    public static func installedGame(shortcut: URL, steamFolder: URL = defaultSteamFolder) -> InstalledGame? {
        guard let appID = appID(shortcut: shortcut) else { return nil }
        return installedGames(steamFolder: steamFolder).first { $0.appID == appID }
    }

    /// Brings the ROMs folder's `steam` folder in line with what's
    /// installed: a `.steam` file for each game that has none, and the
    /// files of games no longer installed taken out. Games on a library
    /// drive that isn't connected keep theirs, so unplugging a drive
    /// doesn't cost them their play history. Only when the ROMs root has a
    /// `steam` folder: Import Steam Games makes it. Returns how many files
    /// were added and removed.
    @discardableResult
    public static func syncShortcuts(romsRoots: [URL], steamFolder: URL = defaultSteamFolder) -> (added: Int, removed: Int) {
        let fileManager = FileManager.default
        guard let folder = romsRoots.map({ $0.appending(path: "steam", directoryHint: .isDirectory) })
            .first(where: { fileManager.fileExists(atPath: $0.path) }),
              fileManager.fileExists(atPath: steamFolder.appending(path: "steamapps").path) else { return (0, 0) }
        let games = installedGames(steamFolder: steamFolder)
        let installed = Set(games.map(\.appID))
        let unreachable = Set(libraries(steamFolder: steamFolder)
            .filter { !fileManager.fileExists(atPath: $0.folder.path) }
            .flatMap(\.appIDs))

        let existing = ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == shortcutExtension }
        var known = Set<String>()
        var removed = 0
        for shortcut in existing {
            guard let appID = appID(shortcut: shortcut) else { continue }
            if installed.contains(appID) || unreachable.contains(appID) {
                known.insert(appID)
            } else if (try? fileManager.removeItem(at: shortcut)) != nil {
                removed += 1
            }
        }
        var added = 0
        for game in games where !known.contains(game.appID) {
            let name = "\(fileName(game.title)) [\(game.appID)].\(shortcutExtension)"
            if (try? Data(game.appID.utf8).write(to: folder.appending(path: name))) != nil { added += 1 }
        }
        return (added, removed)
    }

    /// The `steam://` link that has Steam run a game.
    public static func runURL(appID: String) -> URL {
        URL(string: "steam://rungameid/\(appID)")!
    }

    // MARK: - libraryfolders.vdf

    private struct Library {
        let folder: URL
        let appIDs: [String]
    }

    private static func libraries(steamFolder: URL) -> [Library] {
        let file = steamFolder.appending(path: "steamapps/libraryfolders.vdf")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              case .object(let entries)? = VDF.parse(text)["libraryfolders"] else { return [] }
        return entries.compactMap { _, value in
            guard let path = value["path"]?.string else { return nil }
            var appIDs: [String] = []
            if case .object(let apps)? = value["apps"] { appIDs = apps.map(\.key) }
            return Library(folder: URL(fileURLWithPath: path, isDirectory: true), appIDs: appIDs)
        }
    }

    /// Without characters a file name can't hold.
    private static func fileName(_ title: String) -> String {
        title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Valve's KeyValues text format, which Steam keeps its library files in:
/// quoted keys, each followed by a quoted value or a `{ … }` block.
enum VDF: Equatable {
    case string(String)
    case object([(key: String, value: VDF)])

    static func == (lhs: VDF, rhs: VDF) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)): a == b
        case let (.object(a), .object(b)): a.map(\.key) == b.map(\.key) && a.map(\.value) == b.map(\.value)
        default: false
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The value under `key`, ignoring case as Steam does.
    subscript(key: String) -> VDF? {
        guard case .object(let entries) = self else { return nil }
        return entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// The whole file as one object. Anything malformed ends it early,
    /// keeping what came before.
    static func parse(_ text: String) -> VDF {
        var scanner = Tokens(Array(text.unicodeScalars))
        return .object(scanner.entries())
    }

    private struct Tokens {
        enum Token { case text(String), open, close }
        let scalars: [Unicode.Scalar]
        var index = 0

        init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

        mutating func entries() -> [(key: String, value: VDF)] {
            var entries: [(key: String, value: VDF)] = []
            while let token = next() {
                guard case .text(let key) = token else { break } // a close, or junk
                switch next() {
                case .text(let value)?: entries.append((key, .string(value)))
                case .open?: entries.append((key, .object(self.entries())))
                default: return entries
                }
            }
            return entries
        }

        mutating func next() -> Token? {
            while index < scalars.count {
                let scalar = scalars[index]
                if scalar.properties.isWhitespace {
                    index += 1
                } else if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "/" {
                    while index < scalars.count, scalars[index] != "\n" { index += 1 }
                } else if scalar == "{" {
                    index += 1
                    return .open
                } else if scalar == "}" {
                    index += 1
                    return .close
                } else if scalar == "\"" {
                    index += 1
                    var text = String.UnicodeScalarView()
                    while index < scalars.count, scalars[index] != "\"" {
                        if scalars[index] == "\\", index + 1 < scalars.count {
                            index += 1
                            switch scalars[index] {
                            case "n": text.append("\n")
                            case "t": text.append("\t")
                            default: text.append(scalars[index])
                            }
                        } else {
                            text.append(scalars[index])
                        }
                        index += 1
                    }
                    index += 1
                    return .text(String(text))
                } else {
                    // An unquoted token.
                    var text = String.UnicodeScalarView()
                    while index < scalars.count, !scalars[index].properties.isWhitespace, !"{}\"".unicodeScalars.contains(scalars[index]) {
                        text.append(scalars[index])
                        index += 1
                    }
                    return .text(String(text))
                }
            }
            return nil
        }
    }
}
