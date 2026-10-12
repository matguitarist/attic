import Foundation
import SwiftData
import AtticEmulation
import AtticPersistence

/// Attic was called RomsBox before 1.8 (bundle ID `com.romsbox.app`). This
/// carries a RomsBox setup over on the first launch of Attic, so renaming
/// the app costs the user nothing:
///
/// - settings (the old app's UserDefaults domain),
/// - `~/Library/Application Support/RomsBox` (scraped and custom media,
///   caches) and the Emulation folder's `Config/RomsBox`,
/// - library paths pointing into the old Application Support folder.
///
/// The library itself (`default.store`) doesn't move: its location never
/// depended on the app's name. Scraper credentials move lazily, in
/// `KeychainStore`. Each step runs once and is skipped when there's
/// nothing to bring over, so a fresh install never notices.
enum LegacyRomsBoxMigration {
    static let legacyBundleID = "com.romsbox.app"
    static let legacyKeychainService = "com.romsbox.app.screenscraper"
    private static let legacyFolderName = "RomsBox"
    private static let folderName = "Attic"

    private static let defaultsDoneKey = "migratedSettingsFromRomsBox"
    private static let filesDoneKey = "migratedFilesFromRomsBox"
    /// Defaults keys renamed along with the app (Big Box became Cabinet Mode).
    private static let renamedKeys = ["startInBigBox": "startInCabinet"]

    /// First thing at launch, before any store reads its settings.
    static func migrateSettings(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: defaultsDoneKey) else { return }
        defer { defaults.set(true, forKey: defaultsDoneKey) }
        guard let legacy = defaults.persistentDomain(forName: legacyBundleID) else { return }
        // AppKit's own entries (window frames, split view sizes) are keyed
        // by the old app's type names, so they'd never be read again.
        for (key, value) in legacy where !key.hasPrefix("NS") {
            let newKey = renamedKeys[key] ?? key
            // Never overwrite something already set in Attic itself.
            if defaults.object(forKey: newKey) == nil {
                defaults.set(value, forKey: newKey)
            }
        }
    }

    /// Once the Emulation folder is known and the library is open.
    @MainActor
    static func migrateFiles(emulationFolder: EmulationFolder, modelContainer: ModelContainer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: filesDoneKey) else { return }
        defer { defaults.set(true, forKey: filesDoneKey) }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacySupport = appSupport.appending(path: legacyFolderName, directoryHint: .isDirectory)
        let support = appSupport.appending(path: folderName, directoryHint: .isDirectory)
        if moveIfPossible(legacySupport, to: support) {
            rewriteLibraryPaths(from: legacySupport, to: support, in: modelContainer)
        }

        moveIfPossible(
            emulationFolder.config.appending(path: legacyFolderName, directoryHint: .isDirectory),
            to: emulationFolder.config.appending(path: folderName, directoryHint: .isDirectory)
        )
        // Rewritten under its new name before every launch; the old one is
        // just clutter now.
        try? FileManager.default.removeItem(at: emulationFolder.retroArchConfigDirectory.appending(path: "romsbox-paths.cfg"))
    }

    /// Moves a folder only when the old one exists and the new one doesn't,
    /// so nothing ever gets merged or overwritten.
    @discardableResult
    private static func moveIfPossible(_ source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: destination.path) else { return false }
        return (try? fileManager.moveItem(at: source, to: destination)) != nil
    }

    /// Scraped and custom covers and screenshots are stored as absolute
    /// paths into Application Support.
    @MainActor
    private static func rewriteLibraryPaths(from oldFolder: URL, to newFolder: URL, in container: ModelContainer) {
        let oldPrefix = oldFolder.path.hasSuffix("/") ? oldFolder.path : oldFolder.path + "/"
        let newPrefix = newFolder.path.hasSuffix("/") ? newFolder.path : newFolder.path + "/"
        func moved(_ path: String?) -> String? {
            guard let path, path.hasPrefix(oldPrefix) else { return path }
            return newPrefix + path.dropFirst(oldPrefix.count)
        }
        let context = container.mainContext
        guard let games = try? context.fetch(FetchDescriptor<Game>()) else { return }
        for game in games {
            let cover = moved(game.coverArtPath)
            if cover != game.coverArtPath { game.coverArtPath = cover }
            let screenshot = moved(game.titleScreenPath)
            if screenshot != game.titleScreenPath { game.titleScreenPath = screenshot }
        }
        try? context.save()
    }
}
