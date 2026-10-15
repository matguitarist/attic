import Foundation
import SwiftData
import AtticPersistence
import AtticLibraryScanning

extension Game {
    /// The system's folder in ROMs, which its media folder is named after.
    var systemFolderURL: URL {
        if let system { return system.romsRootURL }
        var url = romAbsoluteURL
        for _ in romRelativePath.split(separator: "/") { url.deleteLastPathComponent() }
        return url
    }

    /// The game's video: the one the scan found, else one in its media
    /// folder (added since).
    var previewVideoURL: URL? {
        if let videoURL, FileManager.default.fileExists(atPath: videoURL.path) { return videoURL }
        let base = MediaFolder.baseURL(forSystemFolder: systemFolderURL, romRelativePath: romRelativePath, kind: .videos)
        return MediaFolder.videoExtensions.map { base.appendingPathExtension($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The game's manual, when there's one in its media folder.
    var manualURL: URL? {
        let base = MediaFolder.baseURL(forSystemFolder: systemFolderURL, romRelativePath: romRelativePath, kind: .manuals)
        let manual = base.appendingPathExtension("pdf")
        return FileManager.default.fileExists(atPath: manual.path) ? manual : nil
    }

    /// The game's logo, when there's one in its media folder.
    var logoURL: URL? {
        MediaFolder.existingFiles(base: MediaFolder.baseURL(forSystemFolder: systemFolderURL, romRelativePath: romRelativePath, kind: .logos)).first
    }

    /// Stores downloaded or picked media for this game where the scanner
    /// finds it (see `MediaFolder`).
    func storeMedia(_ data: Data, fileExtension: String, kind: MediaKind) throws -> URL {
        let url = try MediaFolder.store(data, fileExtension: fileExtension, forSystemFolder: systemFolderURL, romRelativePath: romRelativePath, kind: kind)
        CoverArtThumbnailCache.shared.invalidate(url)
        // A video isn't a thumbnail, but its view watches the same revision.
        return url
    }
}

/// Which games have a logo, from one listing of each logo folder rather
/// than a lookup per game: counting what a list of thousands of games is
/// missing happens as it's drawn.
final class LogoIndex {
    private var names: [URL: Set<String>] = [:]

    func hasLogo(_ game: Game) -> Bool {
        let base = MediaFolder.baseURL(forSystemFolder: game.systemFolderURL, romRelativePath: game.romRelativePath, kind: .logos)
        let folder = base.deletingLastPathComponent()
        if names[folder] == nil {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            names[folder] = Set(files.filter { MediaFolder.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
                .map { ($0 as NSString).deletingPathExtension })
        }
        return names[folder]?.contains(base.lastPathComponent) == true
    }
}

/// Before 1.9.2, scraped and picked media went to Application Support,
/// outside the Emulation folder. This moves what the library still uses
/// into `Media` beside the games, once, and the rest to the
/// Trash.
enum AppSupportMediaMigration {
    private static var folders: [URL] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Attic", directoryHint: .isDirectory)
        return ["ScrapedMedia", "CustomMedia"].map { support.appending(path: $0, directoryHint: .isDirectory) }
    }

    @MainActor
    static func run(in container: ModelContainer) {
        let fileManager = FileManager.default
        let existing = folders.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        let prefixes = existing.map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        func isOld(_ path: String?) -> Bool { path.map { path in prefixes.contains { path.hasPrefix($0) } } ?? false }

        let context = container.mainContext
        guard let games = try? context.fetch(FetchDescriptor<Game>()) else { return }
        for game in games {
            if isOld(game.coverArtPath) {
                game.coverArtPath = moved(game.coverArtURL, for: game, kind: .covers)?.path
            }
            if isOld(game.titleScreenPath) {
                game.titleScreenPath = moved(game.titleScreenURL, for: game, kind: .screenshots)?.path
            }
        }
        try? context.save()
        // What's left belonged to no game in the library.
        for folder in existing {
            try? fileManager.trashItem(at: folder, resultingItemURL: nil)
        }
    }

    @MainActor
    private static func moved(_ url: URL?, for game: Game, kind: MediaKind) -> URL? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? game.storeMedia(data, fileExtension: url.pathExtension, kind: kind)
    }
}
