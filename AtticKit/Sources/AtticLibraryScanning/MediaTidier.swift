import Foundation

/// What tidying a ROMs folder would do; see `MediaTidier`.
public struct MediaTidyPlan: Sendable {
    public struct Move: Sendable, Equatable {
        public let from: URL
        public let to: URL
    }

    public struct GamelistFix: Sendable, Equatable {
        public let from: URL
        public let to: URL
        /// Where its games are.
        public let systemFolder: URL
    }

    /// Batocera-style media in the ROM folders, going to `downloaded_media`.
    public var moves: [Move] = []
    /// Gamelists to rewrite without media paths (which no longer hold)
    /// or entries for games that aren't there: Batocera-style ones in a
    /// ROM folder go to ES-DE's `gamelists/<system>/`, others stay put.
    public var gamelists: [GamelistFix] = []
    /// Whole folders or single files, all going to the Trash.
    public var trash: [URL] = []
    /// PNG and JPEG covers to rewrite as HEIC, after the moves.
    public var compress: [URL] = []
    /// What `trash` takes up.
    public var trashBytes: Int64 = 0

    public var isEmpty: Bool { moves.isEmpty && gamelists.isEmpty && trash.isEmpty && compress.isEmpty }
    var operationCount: Int { moves.count + gamelists.count + trash.count + compress.count }
}

/// Leaves a ROMs folder and the media beside it the way Attic keeps them:
/// games only in `ROMs/<system>/`, their metadata in
/// `gamelists/<system>/gamelist.xml` and their media in
/// `downloaded_media/<system>/<kind>/` (see `MediaFolder`). Everything else
/// other front-ends and scrapers left goes to the Trash, so nothing is
/// lost for good:
///
/// - system folders with no games (ES-DE creates one for every system it
///   knows), with their media and gamelist;
/// - other apps' notes and spare gamelists (`systeminfo.txt`,
///   `gamelist_ARRM.xml`, ARRM's `html_arrm/`…);
/// - media kinds Attic doesn't show (fan art, marquees, 3D boxes…) and
///   media for games that aren't there any more.
///
/// Batocera's in-folder media (`images/x-boxart.png`) is renamed into
/// `downloaded_media` instead, and covers are rewritten as HEIC.
public enum MediaTidier {
    /// Other apps' notes, in a system folder or at a ROMs root.
    static let foreignFileNames: Set<String> = ["systeminfo.txt", "_info.txt", "readme.txt"]
    static let foreignRootFileNames: Set<String> = ["systems.txt"]
    static let foreignFolderNames: Set<String> = ["html_arrm"]
    /// Batocera's media folders inside a system folder.
    static let inFolderMediaFolders: Set<String> = ["images", "videos", "manuals"]
    /// Files that don't make a folder hold games.
    static let ignoredFileNames: Set<String> = ["_sysinfo.txt", ".DS_Store", "gamelist.xml"]
    /// Folders that are games themselves (`Game.ps3`).
    static let gameFolderExtensions: Set<String> = ["ps3"]

    /// Batocera's `<rom>-<suffix>` names, by the kind they become.
    /// `thumb` is usually the box art again, so it's only used when there's
    /// no `boxart`.
    static let inFolderSuffixes: [String: MediaKind] = [
        "boxart": .covers, "image": .screenshots, "mix": .miximages,
        "video": .videos, "manual": .manuals,
    ]

    public static func plan(romsRoots: [URL]) -> MediaTidyPlan {
        var plan = MediaTidyPlan()
        for root in romsRoots {
            addPlan(root: root, into: &plan)
        }
        plan.trashBytes = plan.trash.reduce(0) { $0 + size(of: $1) }
        return plan
    }

    /// Carries out `plan`, reporting progress from 0 to 1. Returns how
    /// many covers were compressed.
    @discardableResult
    public static func apply(_ plan: MediaTidyPlan, progress: (Double) -> Void = { _ in }) -> Int {
        let fileManager = FileManager.default
        let total = Double(max(plan.operationCount, 1))
        var done = 0.0
        // In whole percents, so a long run doesn't flood the caller.
        func step() {
            done += 1
            if Int(done / total * 100) != Int((done - 1) / total * 100) { progress(done / total) }
        }

        for move in plan.moves {
            if !fileManager.fileExists(atPath: move.to.path) {
                try? fileManager.createDirectory(at: move.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileManager.moveItem(at: move.from, to: move.to)
            }
            step()
        }
        for fix in plan.gamelists {
            // The original goes to the Trash, and comes back if the new
            // one can't be written.
            if let text = try? String(contentsOf: fix.from, encoding: .utf8) {
                var trashed: NSURL?
                try? fileManager.createDirectory(at: fix.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if (try? fileManager.trashItem(at: fix.from, resultingItemURL: &trashed)) != nil,
                   (try? cleanedGamelist(text, systemFolder: fix.systemFolder).write(to: fix.to, atomically: true, encoding: .utf8)) == nil,
                   let trashed = trashed as URL? {
                    try? fileManager.moveItem(at: trashed, to: fix.from)
                }
            }
            step()
        }
        for url in plan.trash {
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.trashItem(at: url, resultingItemURL: nil)
            }
            step()
        }
        var compressed = 0
        for url in plan.compress {
            if MediaFolder.compressToHEIC(url) != nil { compressed += 1 }
            step()
        }
        return compressed
    }

    // MARK: - Planning

    private static func addPlan(root: URL, into plan: inout MediaTidyPlan) {
        let fileManager = FileManager.default
        let shared = root.deletingLastPathComponent()
        let mediaRoot = shared.appending(path: MediaFolder.folderName, directoryHint: .isDirectory)
        let gamelistsRoot = shared.appending(path: "gamelists", directoryHint: .isDirectory)

        for name in foreignRootFileNames {
            let url = root.appending(path: name)
            if fileManager.fileExists(atPath: url.path) { plan.trash.append(url) }
        }

        var systemsWithGames: Set<String> = []
        for folder in subfolders(of: root) {
            let name = folder.lastPathComponent
            let games = gameNames(in: folder)
            guard !games.isEmpty else {
                // Nothing to play: the folder goes, with what's beside it.
                plan.trash.append(folder)
                continue
            }
            systemsWithGames.insert(name)

            for child in children(of: folder) {
                let childName = child.lastPathComponent
                let lowered = childName.lowercased()
                if foreignFileNames.contains(lowered) || foreignFolderNames.contains(lowered)
                    || (lowered.hasPrefix("gamelist_") && lowered.hasSuffix(".xml")) {
                    plan.trash.append(child)
                }
            }

            let gamelist = folder.appending(path: "gamelist.xml")
            let esdeFolder = gamelistsRoot.appending(path: name, directoryHint: .isDirectory)
            let destination = esdeFolder.appending(path: "gamelist.xml")
            if fileManager.fileExists(atPath: destination.path) {
                if fileManager.fileExists(atPath: gamelist.path) { plan.trash.append(gamelist) }
                if let text = try? String(contentsOf: destination, encoding: .utf8),
                   cleanedGamelist(text, systemFolder: folder) != text {
                    plan.gamelists.append(.init(from: destination, to: destination, systemFolder: folder))
                }
            } else if fileManager.fileExists(atPath: gamelist.path) {
                plan.gamelists.append(.init(from: gamelist, to: destination, systemFolder: folder))
            } else if fileManager.fileExists(atPath: esdeFolder.path) {
                // A gamelist folder with no gamelist in it.
                plan.trash.append(esdeFolder)
            }

            let systemMedia = mediaRoot.appending(path: name, directoryHint: .isDirectory)
            planInFolderMedia(in: folder, games: games, systemMedia: systemMedia, into: &plan)
            planDownloadedMedia(systemMedia, games: games, into: &plan)
        }

        // Media and gamelists for systems with no games here.
        for parent in [mediaRoot, gamelistsRoot] {
            for folder in subfolders(of: parent) where !systemsWithGames.contains(folder.lastPathComponent) {
                plan.trash.append(folder)
            }
        }
    }

    private static func planInFolderMedia(in folder: URL, games: Set<String>, systemMedia: URL, into plan: inout MediaTidyPlan) {
        var taken = Set<String>() // "<kind>/<game>"
        for mediaFolderName in inFolderMediaFolders.sorted() {
            let mediaFolder = folder.appending(path: mediaFolderName, directoryHint: .isDirectory)
            let files = children(of: mediaFolder).filter { !isDirectory($0) }
            guard !files.isEmpty || FileManager.default.fileExists(atPath: mediaFolder.path) else { continue }

            // Box art first, so a `thumb` only fills in where there's none.
            let parsed = files.compactMap { file -> (file: URL, game: String, suffix: String)? in
                let stem = file.deletingPathExtension().lastPathComponent
                guard let dash = stem.lastIndex(of: "-") else { return nil }
                return (file, String(stem[..<dash]), String(stem[stem.index(after: dash)...]).lowercased())
            }.sorted { ($0.suffix == "thumb" ? 1 : 0) < ($1.suffix == "thumb" ? 1 : 0) }

            for (file, game, suffix) in parsed where games.contains(game) {
                guard let kind = suffix == "thumb" ? .covers : inFolderSuffixes[suffix] else { continue }
                let key = "\(kind.rawValue)/\(game)"
                let base = systemMedia.appending(path: kind.rawValue).appending(path: game)
                guard !taken.contains(key), MediaFolder.existingFiles(base: base).isEmpty else { continue }
                taken.insert(key)
                let destination = base.appendingPathExtension(file.pathExtension.lowercased())
                plan.moves.append(.init(from: file, to: destination))
                if kind == .covers, isCompressible(destination) { plan.compress.append(destination) }
            }
            // What's left (marquees, fan art, cartridges…) goes with the folder.
            plan.trash.append(mediaFolder)
        }
    }

    private static func planDownloadedMedia(_ systemMedia: URL, games: Set<String>, into plan: inout MediaTidyPlan) {
        for kindFolder in subfolders(of: systemMedia) {
            guard let kind = MediaKind(rawValue: kindFolder.lastPathComponent) else {
                plan.trash.append(kindFolder)
                continue
            }
            for file in files(under: kindFolder) {
                let relative = String(file.path.dropFirst(kindFolder.path.count + 1))
                if !games.contains((relative as NSString).deletingPathExtension) {
                    plan.trash.append(file)
                } else if kind == .covers, isCompressible(file) {
                    plan.compress.append(file)
                }
            }
        }
    }

    // MARK: - Files

    /// The games in a system folder, as paths within it without their
    /// extension: what media files are named after.
    static func gameNames(in folder: URL) -> Set<String> {
        var names = Set<String>()
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return names }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let lowered = name.lowercased()
            if isDirectory(url) {
                if enumerator.level == 1, inFolderMediaFolders.contains(lowered) || foreignFolderNames.contains(lowered) {
                    enumerator.skipDescendants()
                } else if gameFolderExtensions.contains(url.pathExtension.lowercased()) {
                    names.insert(relativeName(url, in: folder))
                    enumerator.skipDescendants()
                }
                continue
            }
            if ignoredFileNames.contains(name) || foreignFileNames.contains(lowered)
                || (lowered.hasPrefix("gamelist") && lowered.hasSuffix(".xml")) { continue }
            names.insert(relativeName(url, in: folder))
        }
        return names
    }

    private static func relativeName(_ url: URL, in folder: URL) -> String {
        let relative = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
        return (relative as NSString).deletingPathExtension
    }

    /// PNGs and JPEGs, except palette PNGs: already that small, HEIC
    /// doesn't beat them, so they'd come up again on every tidy.
    private static func isCompressible(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return true
        case "png":
            // Byte 25 of a PNG is the colour type, 3 for a palette.
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let header = try? handle.read(upToCount: 26), header.count == 26 else { return true }
            try? handle.close()
            return header[25] != 3
        default:
            return false
        }
    }

    private static func children(of folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func subfolders(of folder: URL) -> [URL] {
        children(of: folder).filter(isDirectory)
    }

    private static func files(under folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { !isDirectory($0) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        if !isDirectory(url) {
            return Int64((try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        return enumerator.reduce(Int64(0)) { total, item in
            total + Int64(((item as? URL).flatMap { try? $0.resourceValues(forKeys: keys).totalFileAllocatedSize }) ?? 0)
        }
    }

    // MARK: - Gamelists

    /// Batocera's per-game media tags, whose paths point at files that
    /// have moved; ES-DE finds media by name instead.
    static let mediaTags = ["image", "thumbnail", "screenshot", "titlescreen", "video", "marquee", "fanart", "manual", "boxart", "boxback",
                            "cartridge", "wheel", "mix", "titleshot", "map", "bezel", "magazine", "music"]

    /// Without media paths, and without entries for games that aren't in
    /// `systemFolder` any more.
    static func cleanedGamelist(_ text: String, systemFolder: URL) -> String {
        let games = try! NSRegularExpression(pattern: "[ \\t]*<game\\b[^>]*>.*?</game>[ \\t]*\\r?\\n?", options: .dotMatchesLineSeparators)
        let path = try! NSRegularExpression(pattern: "<path>([^<]*)</path>")
        var result = withoutMediaPaths(text)
        let nsText = result as NSString
        for match in games.matches(in: result, range: NSRange(location: 0, length: nsText.length)).reversed() {
            let entry = nsText.substring(with: match.range)
            guard let pathMatch = path.firstMatch(in: entry, range: NSRange(location: 0, length: (entry as NSString).length)) else { continue }
            let relative = ESDEGamelistMapper.normalizeRelativePath(unescaped((entry as NSString).substring(with: pathMatch.range(at: 1))))
            if !FileManager.default.fileExists(atPath: systemFolder.appending(path: relative).path) {
                result = (result as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        return result
    }

    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func withoutMediaPaths(_ text: String) -> String {
        let tags = mediaTags.joined(separator: "|")
        let pattern = "[ \\t]*(?:<(\(tags))>[^<]*</\\1>|<(?:\(tags))\\s*/>)[ \\t]*\\r?\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
