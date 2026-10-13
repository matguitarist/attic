import AppKit
import SwiftData
import AtticModels
import AtticPersistence

/// Each collection also lives as a folder, `Emulation/Collections/<Name>/`:
/// its `collection.json` (see `CollectionFile`), its `logo` and its
/// `artwork`. Attic rewrites the file whenever the library is saved, so
/// collections move and back up with the Emulation folder, come back if
/// the library is ever reset, and export as just that folder.
@MainActor
enum CollectionFolders {
    static func root(in emulationRoot: URL) -> URL {
        emulationRoot.appending(path: EmulationLayout.collections, directoryHint: .isDirectory)
    }

    // MARK: - Keeping the folders up to date

    /// Writes every collection's file, renaming its folder along with it.
    /// Never deletes a folder: only deleting the collection does.
    static func save(_ collections: [GameCollection], root: URL) {
        defer { cachedFolders = nil }
        let folders = foldersByID(in: root)
        for collection in collections {
            let folder = folder(for: collection, root: root, existing: folders)
            let target = root.appending(path: CollectionFile.folderName(for: collection.name), directoryHint: .isDirectory)
            var current = folder
            if folder.lastPathComponent != target.lastPathComponent, !FileManager.default.fileExists(atPath: target.path),
               FileManager.default.fileExists(atPath: folder.path),
               (try? FileManager.default.moveItem(at: folder, to: target)) != nil {
                current = target
            }
            guard let data = try? file(for: collection).encoded() else { continue }
            let url = current.appending(path: CollectionFile.fileName)
            if (try? Data(contentsOf: url)) == data { continue }
            try? FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Moves a deleted collection's folder to the Trash.
    static func remove(_ collection: GameCollection, root: URL) {
        defer { cachedFolders = nil }
        guard let folder = foldersByID(in: root)[collection.collectionID] else { return }
        try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
    }

    /// Loads the collection folders in `root` the library doesn't have:
    /// one copied in by hand, or all of them for a reset library or a new
    /// Mac. (A deleted collection's folder goes to the Trash, so it
    /// doesn't come back.) Returns how many.
    @discardableResult
    static func loadNewFolders(context: ModelContext, root: URL) -> Int {
        cachedFolders = nil
        guard (try? context.fetchCount(FetchDescriptor<Game>())) ?? 0 > 0,
              let existing = try? context.fetch(FetchDescriptor<GameCollection>()) else { return 0 }
        let known = Set(existing.map(\.collectionID))
        var loaded = 0
        for (id, folder) in foldersByID(in: root) where !known.contains(id) {
            if importCollection(from: folder, context: context, root: root, keepID: true) != nil { loaded += 1 }
        }
        return loaded
    }

    // MARK: - Import and export

    struct ImportResult {
        let collection: GameCollection
        let found: Int
        let missing: Int
    }

    /// Reads a collection folder (or its `collection.json`), finding its
    /// games by system and path, else by title. Its pictures come along.
    @discardableResult
    static func importCollection(from url: URL, context: ModelContext, root: URL, keepID: Bool = false) -> ImportResult? {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? url : url.deletingLastPathComponent()
        let fileURL = isFolder ? url.appending(path: CollectionFile.fileName) : url
        guard let data = try? Data(contentsOf: fileURL), let file = try? CollectionFile.decoded(from: data),
              let games = try? context.fetch(FetchDescriptor<Game>()),
              let existing = try? context.fetch(FetchDescriptor<GameCollection>()) else { return nil }

        let byKey = Dictionary(games.map { ($0.collectionKey, $0) }, uniquingKeysWith: { first, _ in first })
        let bySystemTitle = Dictionary(games.map { ("\($0.systemCanonicalID)/\($0.title.lowercased())", $0) }, uniquingKeysWith: { first, _ in first })
        let byTitle = Dictionary(games.map { ($0.title.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var found: [Game] = []
        var missing = 0
        for entry in file.games {
            if let game = byKey[entry.key] ?? bySystemTitle["\(entry.system)/\(entry.title.lowercased())"] ?? byTitle[entry.title.lowercased()] {
                found.append(game)
            } else {
                missing += 1
            }
        }

        let names = Set(existing.map(\.name))
        var name = file.name
        var number = 2
        while names.contains(name) {
            name = "\(file.name) \(number)"
            number += 1
        }
        let collection = GameCollection(name: name)
        if keepID, !existing.contains(where: { $0.collectionID == file.id }) {
            collection.collectionID = file.id
        }
        context.insert(collection)
        collection.games = found
        collection.search = CollectionSearch(including: file.including, excluding: file.excluding)
        collection.searchSystemID = file.system
        collection.addsMatchingGames = file.addsMatchingGames
        collection.excludedGameKeys = file.excluded
        try? context.save()

        save([collection], root: root)
        // Pictures from elsewhere are copied in. A logo under another name
        // (mario.png beside the file) becomes the logo too.
        let destination = self.folder(for: collection, root: root, existing: foldersByID(in: root))
        let isElsewhere = destination.standardizedFileURL != folder.standardizedFileURL
        for picture in [CollectionFile.logoName, CollectionFile.artworkName] {
            if let source = image(named: picture, in: folder) {
                if isElsewhere { setImage(source, as: picture, for: collection, root: root) }
            } else if picture == CollectionFile.logoName, let source = looseLogo(in: folder, name: file.name) {
                setImage(source, as: picture, for: collection, root: root)
            }
        }
        return ImportResult(collection: collection, found: found.count, missing: missing)
    }

    /// Asks where to put a copy of the collection's folder, and puts it there.
    static func export(_ collection: GameCollection, root: URL) {
        save([collection], root: root)
        let source = folder(for: collection, root: root, existing: foldersByID(in: root))
        let panel = NSSavePanel()
        panel.nameFieldStringValue = CollectionFile.folderName(for: collection.name)
        panel.message = String(localized: "The collection is saved as a folder, with its list of games and its pictures. Import it with File › Import Collection….")
        panel.prompt = String(localized: "Export")
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try? FileManager.default.copyItem(at: source, to: destination)
        }
    }

    static func showInFinder(_ collection: GameCollection, root: URL) {
        save([collection], root: root)
        let folder = folder(for: collection, root: root, existing: foldersByID(in: root))
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - Pictures

    static func image(named name: String, for collection: GameCollection, root: URL) -> URL? {
        image(named: name, in: folder(for: collection, root: root, existing: foldersByID(in: root)))
    }

    /// Copies `source` in as the collection's `name` picture (logo or
    /// artwork), replacing the earlier one; nil removes it.
    static func setImage(_ source: URL?, as name: String, for collection: GameCollection, root: URL) {
        save([collection], root: root)
        let folder = folder(for: collection, root: root, existing: foldersByID(in: root))
        if let old = image(named: name, in: folder) { try? FileManager.default.trashItem(at: old, resultingItemURL: nil) }
        guard let source else { return }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        try? FileManager.default.copyItem(at: source, to: folder.appending(path: "\(name).\(ext)"))
    }

    private static func image(named name: String, in folder: URL) -> URL? {
        images(in: folder).first { $0.deletingPathExtension().lastPathComponent.lowercased() == name }
    }

    private static func images(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { CollectionLogos.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A picture in a collection's folder not named logo or artwork that's
    /// its logo: named like the collection (mario.png for Mario), or the
    /// only picture there.
    private static func looseLogo(in folder: URL, name: String) -> URL? {
        let others = images(in: folder).filter {
            ![CollectionFile.logoName, CollectionFile.artworkName].contains($0.deletingPathExtension().lastPathComponent.lowercased())
        }
        let names = SeriesTemplate.logoNames(for: name)
        return names.lazy.compactMap { logoName in others.first { $0.deletingPathExtension().lastPathComponent.lowercased() == logoName } }.first
            ?? (others.count == 1 ? others[0] : nil)
    }

    // MARK: - Files

    static func file(for collection: GameCollection) -> CollectionFile {
        CollectionFile(
            id: collection.collectionID,
            name: collection.name,
            including: collection.searchIncluding,
            excluding: collection.searchExcluding,
            system: collection.searchSystemID,
            addsMatchingGames: collection.addsMatchingGames,
            games: collection.games
                .sorted { $0.collectionKey < $1.collectionKey }
                .map { CollectionFile.Entry(system: $0.systemCanonicalID, path: $0.romRelativePath, title: $0.title) },
            excluded: collection.excludedGameKeys.sorted()
        )
    }

    /// The collection's folder: where its file already is, else named
    /// after it.
    private static func folder(for collection: GameCollection, root: URL, existing: [UUID: URL]) -> URL {
        existing[collection.collectionID] ?? root.appending(path: CollectionFile.folderName(for: collection.name), directoryHint: .isDirectory)
    }

    /// The last `foldersByID` result: Cabinet Mode and the side panel ask
    /// for pictures on every redraw. Cleared whenever folders change.
    private static var cachedFolders: (root: URL, byID: [UUID: URL])?

    /// Collection folders under `root`, by the ID in their file.
    private static func foldersByID(in root: URL) -> [UUID: URL] {
        if let cachedFolders, cachedFolders.root == root { return cachedFolders.byID }
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var byID: [UUID: URL] = [:]
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appending(path: CollectionFile.fileName)),
                  let file = try? CollectionFile.decoded(from: data) else { continue }
            byID[file.id] = folder
        }
        cachedFolders = (root, byID)
        return byID
    }
}

/// Logos for collections, from a folder of one's own: a theme's logo
/// folder (`mario.png`, `zelda.png`…) or any folder of pictures named
/// after series. Attic ships none: they're the series owners' marks.
enum CollectionLogos {
    /// The folder's path, set in Settings.
    static let folderKey = "collectionLogosFolder"

    static var folder: URL? {
        guard let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp"]

    /// The folder's logo for a collection called `name`, if it has one.
    static func logo(forCollectionNamed name: String) -> URL? {
        guard let folder else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var byName: [String: URL] = [:]
        for file in files where imageExtensions.contains(file.pathExtension.lowercased()) {
            let key = file.deletingPathExtension().lastPathComponent.lowercased()
            if byName[key] == nil { byName[key] = file }
        }
        return SeriesTemplate.logoNames(for: name).lazy.compactMap { byName[$0] }.first
    }

    /// Gives each collection without a logo the folder's one for it.
    /// Returns how many got one.
    @MainActor @discardableResult
    static func addMissing(to collections: [GameCollection], root: URL) -> Int {
        var added = 0
        for collection in collections where CollectionFolders.image(named: CollectionFile.logoName, for: collection, root: root) == nil {
            guard let logo = logo(forCollectionNamed: collection.name) else { continue }
            CollectionFolders.setImage(logo, as: CollectionFile.logoName, for: collection, root: root)
            added += 1
        }
        return added
    }
}
