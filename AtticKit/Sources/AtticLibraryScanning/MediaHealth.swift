import Foundation
import ImageIO
import Synchronization
import AtticModels

/// How complete and sound each system's media is: how many of its games
/// have each kind, and the files that are there but wrong — blank,
/// unreadable, small, or a cover the library doesn't use.
public enum MediaHealth {
    /// A game to check, as the library knows it.
    public struct Game: Sendable {
        public let title: String
        public let system: CanonicalSystemID
        /// The system's folder in ROMs, its media folder's name.
        public let systemFolder: URL
        public let romRelativePath: String
        /// The picture the library shows as its cover.
        public let coverPath: String?
        /// Its file's path, the library's name for it.
        public let path: String?

        public init(title: String, system: CanonicalSystemID, systemFolder: URL, romRelativePath: String, coverPath: String?,
                    path: String? = nil) {
            self.path = path
            self.title = title
            self.system = system
            self.systemFolder = systemFolder
            self.romRelativePath = romRelativePath
            self.coverPath = coverPath
        }
    }

    public enum Problem: Hashable, Sendable, Codable {
        /// Entirely transparent: nothing to see.
        case blank
        /// Empty, or not a picture or video that opens.
        case unreadable
        /// Too small to look right (see `isTooSmall`).
        case small(width: Int, height: Int)
        /// The game has a 2D box, but the library shows another picture
        /// (a screenshot, from before the box was there) until a rescan.
        case coverNotBox
    }

    public struct Finding: Sendable, Identifiable, Hashable {
        public var id: String { file.path + "|" + kind.rawValue }
        public let title: String
        public let kind: MediaKind
        public let problem: Problem
        public let file: URL
        /// The game's file's path.
        public let gamePath: String?
    }

    public struct Report: Sendable, Identifiable {
        public var id: String { folder.path }
        public let system: CanonicalSystemID
        /// The system's folder in ROMs.
        public let folder: URL
        public let games: Int
        /// The kinds that apply to the system, in order.
        public let kinds: [MediaKind]
        /// How many games have each kind.
        public let have: [MediaKind: Int]
        public let findings: [Finding]

        public func missing(_ kind: MediaKind) -> Int { games - (have[kind] ?? 0) }
    }

    /// Each file's last result, kept between checks so only new or
    /// changed files are opened again.
    public struct Cache: Codable, Sendable {
        struct Entry: Codable, Sendable {
            let modified: Date
            let size: Int
            let problem: Problem?
        }
        var entries: [String: Entry] = [:]

        public init() {}

        public static func load(from url: URL) -> Cache {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) } ?? Cache()
        }

        public func save(to url: URL) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }

    /// One report per system folder, files checked in parallel; returns
    /// the cache for next time too.
    public static func check(_ games: [Game], cache: Cache = Cache()) -> (reports: [Report], cache: Cache) {
        let bySystem = Dictionary(grouping: games) { $0.systemFolder.standardizedFileURL.path }
        let systems = bySystem.values.sorted { $0[0].systemFolder.lastPathComponent < $1[0].systemFolder.lastPathComponent }

        // What each game has, from one listing per kind folder…
        struct Item: Sendable {
            let system: Int
            let game: Game
            let kind: MediaKind
            let file: URL
        }
        var listed: [Item] = []
        var have: [[MediaKind: Int]] = Array(repeating: [:], count: systems.count)
        for (index, games) in systems.enumerated() {
            let root = MediaFolder.root(forSystemFolder: games[0].systemFolder)
            for kind in MediaFolder.kinds(for: games[0].system) {
                let files = listing(root.appending(path: kind.rawValue, directoryHint: .isDirectory))
                for game in games {
                    guard let file = files[(game.romRelativePath as NSString).deletingPathExtension] else { continue }
                    have[index][kind, default: 0] += 1
                    listed.append(Item(system: index, game: game, kind: kind, file: file))
                }
            }
        }

        // …then every file looked at, all at once, unless it's unchanged
        // since the last check.
        let found = Mutex<[[Finding]]>(Array(repeating: [], count: systems.count))
        let entries = Mutex<[String: Cache.Entry]>([:])
        let items = listed
        DispatchQueue.concurrentPerform(iterations: items.count) { index in
            let item = items[index]
            let values = try? item.file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            var problem: Problem?
            if let known = cache.entries[item.file.path], known.modified == modified, known.size == size {
                problem = known.problem
            } else {
                problem = self.problem(with: item.file, kind: item.kind)
            }
            entries.withLock { $0[item.file.path] = Cache.Entry(modified: modified, size: size, problem: problem) }
            if problem == nil, item.kind == .covers, let cover = item.game.coverPath,
               URL(fileURLWithPath: cover).standardizedFileURL != item.file.standardizedFileURL {
                problem = .coverNotBox
            }
            guard let problem else { return }
            let finding = Finding(title: item.game.title, kind: item.kind, problem: problem, file: item.file,
                                  gamePath: item.game.path)
            found.withLock { $0[item.system].append(finding) }
        }
        let findings = found.withLock { $0 }
        var newCache = Cache()
        newCache.entries = entries.withLock { $0 }
        let reports = systems.enumerated().map { index, games in
            Report(system: games[0].system, folder: games[0].systemFolder, games: games.count,
                   kinds: MediaFolder.kinds(for: games[0].system), have: have[index],
                   findings: findings[index].sorted { ($0.title, $0.kind.rawValue) < ($1.title, $1.kind.rawValue) })
        }
        return (reports, newCache)
    }

    /// A kind's files by their path without extension, from one walk of
    /// its folder rather than a look per game.
    static func listing(_ folder: URL) -> [String: URL] {
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles]) else { return [:] }
        let extensions = Set(MediaFolder.imageExtensions + MediaFolder.videoExtensions + ["pdf"])
        let base = folder.standardizedFileURL.path + "/"
        var files: [String: URL] = [:]
        for case let url as URL in walk where extensions.contains(url.pathExtension.lowercased()) {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            files[(String(path.dropFirst(base.count)) as NSString).deletingPathExtension] = url
        }
        return files
    }

    /// What's wrong with a file, if anything.
    static func problem(with file: URL, kind: MediaKind) -> Problem? {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard bytes > 0 else { return .unreadable }
        guard MediaFolder.imageExtensions.contains(file.pathExtension.lowercased()) else { return nil }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let size = MediaQuality.size(ofImage: file) else { return .unreadable }
        if isBlank(source) { return .blank }
        if isTooSmall(size, kind: kind) {
            return .small(width: Int(size.width), height: Int(size.height))
        }
        return nil
    }

    /// Whether `data` is a better picture than `file`: one that opens and
    /// shows something, and, unless `file` is blank or broken, is
    /// noticeably larger.
    public static func isBetter(_ data: Data, than file: URL, kind: MediaKind) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              !isBlank(source) else { return false }
        switch problem(with: file, kind: kind) {
        case .blank?, .unreadable?: return true
        default:
            guard let current = MediaQuality.size(ofImage: file) else { return true }
            return CGFloat(max(width, height)) >= max(current.width, current.height) * 1.25
        }
    }

    /// Too small to look right anywhere: well under `MediaQuality`'s bar,
    /// which is for when there's something sharper to get.
    static func isTooSmall(_ size: CGSize, kind: MediaKind) -> Bool {
        let longest = max(size.width, size.height)
        switch kind {
        case .covers, .boxes3D, .physicalMedia, .marquees: return longest < 350
        case .logos: return longest < 200
        case .fanart: return longest < 960
        case .screenshots, .videos, .manuals, .bezels: return false
        }
    }

    /// Nothing drawn: every pixel of a small copy clear. Only pictures with
    /// transparency are drawn to see.
    static func isBlank(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard properties?[kCGImagePropertyHasAlpha] as? Bool == true,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 48] as CFDictionary) else { return false }
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return !stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 8 }
        }
    }
}
