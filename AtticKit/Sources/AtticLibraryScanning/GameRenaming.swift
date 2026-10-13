import Foundation

/// Gives a game's file another name (No-Intro's, from a DAT), and takes
/// along what's named after it: its media, its gamelist entry and
/// playlists, and the saves and states of a game that isn't zipped.
public enum GameRenaming {
    public struct Moved: Equatable, Sendable {
        public let from: URL
        public let to: URL
        /// Each media file moved, old path to new (with symbolic links
        /// resolved, as /var is /private/var).
        public let media: [String: String]
    }

    /// A file name for `name`: no folder separators.
    public static func fileStem(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Renames `file` to `newStem` (keeping its extension). `systemFolder`
    /// is the system's ROMs folder; `saveFolders`, the system's Saves and
    /// States folders. nil, and nothing changed, when another file
    /// already has the name.
    public static func rename(_ file: URL, to newStem: String, systemFolder: URL, saveFolders: [URL]) -> Moved? {
        let oldStem = file.deletingPathExtension().lastPathComponent
        let newStem = fileStem(newStem)
        guard !newStem.isEmpty, newStem != oldStem else { return nil }
        let ext = file.pathExtension
        let target = file.deletingLastPathComponent().appending(path: ext.isEmpty ? newStem : "\(newStem).\(ext)")
        guard move(file, to: target) else { return nil }

        var media: [String: String] = [:]
        let relativeFolder = relativePath(of: file.deletingLastPathComponent(), in: systemFolder)
        for kind in MediaKind.allCases {
            var folder = MediaFolder.root(forSystemFolder: systemFolder).appending(path: kind.rawValue, directoryHint: .isDirectory)
            if !relativeFolder.isEmpty { folder.append(path: relativeFolder, directoryHint: .isDirectory) }
            for item in files(in: folder) where item.deletingPathExtension().lastPathComponent == oldStem {
                let moved = item.deletingLastPathComponent().appending(path: "\(newStem).\(item.pathExtension)")
                // Resolved while it's there to resolve.
                let old = item.resolvingSymlinksInPath().path
                if move(item, to: moved) { media[old] = moved.resolvingSymlinksInPath().path }
            }
        }

        ReplacedGameFile.repoint(in: file.deletingLastPathComponent(), from: file.lastPathComponent, to: target.lastPathComponent)

        // A zipped game's saves are named after the file inside, which
        // keeps its name.
        if !["zip", "7z"].contains(ext.lowercased()) {
            for folder in saveFolders {
                for item in files(in: folder) {
                    let name = item.lastPathComponent
                    guard name.hasPrefix(oldStem + ".") else { continue }
                    move(item, to: folder.appending(path: newStem + name.dropFirst(oldStem.count)))
                }
            }
        }
        return Moved(from: file, to: target, media: media)
    }

    /// Moves a file, unless something else has the name already. A
    /// change of case only goes through a temporary name, which a
    /// case-insensitive disk needs.
    @discardableResult
    static func move(_ from: URL, to: URL) -> Bool {
        let manager = FileManager.default
        let caseOnly = from.path.lowercased() == to.path.lowercased()
        guard caseOnly || !manager.fileExists(atPath: to.path) else { return false }
        do {
            if caseOnly {
                let step = from.deletingLastPathComponent().appending(path: ".attic-rename-\(UUID().uuidString)")
                try manager.moveItem(at: from, to: step)
                try manager.moveItem(at: step, to: to)
            } else {
                try manager.moveItem(at: from, to: to)
            }
            return true
        } catch {
            return false
        }
    }

    private static func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    private static func relativePath(of folder: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = folder.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return "" }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
