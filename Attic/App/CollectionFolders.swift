import AppKit
import SwiftData
import AtticModels
import AtticPersistence
import AtticLibraryScanning

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

    /// Collections deleted here, so a folder that couldn't go to the Trash
    /// (on a network share, say) doesn't bring one back.
    static let deletedIDsKey = "deletedCollectionIDs"

    static var deletedIDs: Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: deletedIDsKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// Moves a deleted collection's folder to the Trash.
    static func remove(_ collection: GameCollection, root: URL) {
        defer { cachedFolders = nil }
        UserDefaults.standard.set(Array(deletedIDs.union([collection.collectionID])).map(\.uuidString), forKey: deletedIDsKey)
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
        let known = Set(existing.map(\.collectionID)).union(deletedIDs)
        var loaded = 0
        for (id, folder) in foldersByID(in: root) where !known.contains(id) {
            if importCollection(from: folder, context: context, root: root, keepID: true) != nil { loaded += 1 }
        }
        return loaded
    }

    // MARK: - Import and export

    /// Whether `url` is an exported collection: a folder with a
    /// collection.json, or the file itself.
    static func isCollection(_ url: URL) -> Bool {
        ESDECustomCollection.isCollectionFile(url)
            || url.lastPathComponent.lowercased() == CollectionFile.fileName.lowercased()
            || FileManager.default.fileExists(atPath: url.appending(path: CollectionFile.fileName).path)
    }

    struct ImportResult {
        let collection: GameCollection
        let found: Int
        let missing: Int
    }

    /// Reads a collection folder (or its `collection.json`), finding its
    /// games by system and path, else by title. Its pictures come along.
    @discardableResult
    static func importCollection(from url: URL, context: ModelContext, root: URL, keepID: Bool = false) -> ImportResult? {
        if ESDECustomCollection.isCollectionFile(url) { return importESDECollection(from: url, context: context, root: root) }
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

        let collection = GameCollection(name: uniqueName(file.name, among: existing))
        if keepID, !existing.contains(where: { $0.collectionID == file.id }) {
            collection.collectionID = file.id
        }
        context.insert(collection)
        collection.games = found
        collection.search = file.search
        collection.searchSystemID = file.system
        collection.addsMatchingGames = file.addsMatchingGames
        collection.excludedGameKeys = file.excluded
        collection.isHidden = file.hidden ?? false
        try? context.save()

        save([collection], root: root)
        // Pictures from elsewhere are copied in. A logo under another name
        // (mario.png beside the file) becomes the logo too.
        let destination = self.folder(for: collection, root: root, existing: foldersByID(in: root))
        let isElsewhere = destination.standardizedFileURL != folder.standardizedFileURL
        for picture in [CollectionFile.logoName, CollectionFile.artworkName, CollectionFile.fanartName] {
            if let source = image(named: picture, in: folder) {
                if isElsewhere { setImage(source, as: picture, for: collection, root: root) }
            } else if picture == CollectionFile.logoName, let source = looseLogo(in: folder, name: file.name) {
                setImage(source, as: picture, for: collection, root: root)
            }
        }
        return ImportResult(collection: collection, found: found.count, missing: missing)
    }

    /// An ES-DE (or Batocera) custom collection: its games found by their
    /// system folder and path, else by file name; its logo from the logos
    /// folder, if there's one for its name.
    static func importESDECollection(from url: URL, context: ModelContext, root: URL) -> ImportResult? {
        guard let file = ESDECustomCollection.read(url), !file.entries.isEmpty,
              let games = try? context.fetch(FetchDescriptor<Game>()),
              let existing = try? context.fetch(FetchDescriptor<GameCollection>()) else { return nil }

        func stem(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased() }
        let byPath = Dictionary(games.map { ("\($0.systemFolderURL.lastPathComponent.lowercased())/\($0.romRelativePath.lowercased())", $0) },
                                uniquingKeysWith: { first, _ in first })
        let byFolderStem = Dictionary(games.map { ("\($0.systemFolderURL.lastPathComponent.lowercased())/\(stem($0.romRelativePath))", $0) },
                                      uniquingKeysWith: { first, _ in first })
        let byStem = Dictionary(games.map { (stem($0.romRelativePath), $0) }, uniquingKeysWith: { first, _ in first })
        var found: [Game] = []
        var missing = 0
        for entry in file.entries {
            let folder = entry.systemFolder.lowercased()
            if let game = byPath["\(folder)/\(entry.path.lowercased())"] ?? byFolderStem["\(folder)/\(stem(entry.path))"] ?? byStem[stem(entry.path)] {
                if !found.contains(where: { $0.persistentModelID == game.persistentModelID }) { found.append(game) }
            } else {
                missing += 1
            }
        }

        let collection = GameCollection(name: uniqueName(file.name, among: existing))
        context.insert(collection)
        collection.games = found
        try? context.save()
        save([collection], root: root)
        return ImportResult(collection: collection, found: found.count, missing: missing)
    }

    /// `name`, numbered when a collection already has it.
    private static func uniqueName(_ name: String, among existing: [GameCollection]) -> String {
        let names = Set(existing.map(\.name))
        var unique = name
        var number = 2
        while names.contains(unique) {
            unique = "\(name) \(number)"
            number += 1
        }
        return unique
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

    /// The collection's folder, where its file and pictures are.
    static func folderURL(for collection: GameCollection, root: URL) -> URL {
        folder(for: collection, root: root, existing: foldersByID(in: root))
    }

    /// A picture or video in a collection's folder, by name without its
    /// extension.
    nonisolated static func file(named name: String, inFolder folder: URL) -> URL? {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { (CollectionLogos.imageExtensions.union(MediaFolder.videoExtensions)).contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first { $0.deletingPathExtension().lastPathComponent.lowercased() == name }
    }

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
            ![CollectionFile.logoName, CollectionFile.artworkName, CollectionFile.fanartName].contains($0.deletingPathExtension().lastPathComponent.lowercased())
        }
        let names = SeriesTemplate.logoNames(for: name)
        return names.lazy.compactMap { logoName in others.first { $0.deletingPathExtension().lastPathComponent.lowercased() == logoName } }.first
            ?? (others.count == 1 ? others[0] : nil)
    }

    // MARK: - Files

    static func file(for collection: GameCollection) -> CollectionFile {
        var file = CollectionFile(
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
        file.setCriteria(from: collection.search)
        file.hidden = collection.isHidden ? true : nil
        return file
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

/// The pictures a collection's logo can be.
enum CollectionLogos {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp"]
}
