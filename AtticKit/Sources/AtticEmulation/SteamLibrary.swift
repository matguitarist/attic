import Foundation
import AtticModels
import SteamKit

/// Mac games installed through Steam.
///
/// SteamKit reads Steam's libraries (`libraryfolders.vdf`) and the
/// `appmanifest_<app ID>.acf` in each. This keeps the games that are fully
/// installed and have a Mac app (so Proton-less Windows builds and tools
/// like the redistributables stay out), and keeps a `<Title> [<app ID>].steam`
/// file (holding the app ID) in the ROMs folder's `steam` folder for each,
/// so they show up in the library like any other game. They're played
/// through Steam (`steam://rungameid/<app ID>`), which keeps them updated
/// and signed in.
public enum SteamLibrary {
    public struct InstalledGame: Equatable, Sendable {
        public let appID: String
        public let title: String
        /// `steamapps/common/<install dir>` in its library folder.
        public let folder: URL
    }

    /// Steam's own data folder, where its first library lives.
    public static var defaultSteamFolder: URL { Steam.defaultRoot }

    public static let shortcutExtension = "steam"

    /// Steam's library folders that are connected: its own, and any added
    /// on other drives.
    public static func libraryFolders(steamFolder: URL = defaultSteamFolder) -> [URL] {
        Steam(root: steamFolder).libraries().filter(\.isReachable).map(\.folder)
    }

    /// Every fully installed game with a Mac app, by title.
    public static func installedGames(steamFolder: URL = defaultSteamFolder) -> [InstalledGame] {
        Steam(root: steamFolder).games().filter { $0.macApp() != nil }
            .map { InstalledGame(appID: $0.id, title: $0.name, folder: $0.folder) }
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
        let steam = Steam(root: steamFolder)
        guard let folder = romsRoots.map({ $0.appending(path: "steam", directoryHint: .isDirectory) })
            .first(where: { fileManager.fileExists(atPath: $0.path) }),
              steam.isInstalled else { return (0, 0) }
        let games = installedGames(steamFolder: steamFolder)
        let installed = Set(games.map(\.appID))
        let unreachable = Set(steam.libraries().filter { !$0.isReachable }.flatMap(\.apps.keys))

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

    /// Without characters a file name can't hold.
    private static func fileName(_ title: String) -> String {
        title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
