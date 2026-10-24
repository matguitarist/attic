import AppKit
import Foundation
import AtticModels
import AtticPersistence
import AtticLibraryScanning
import AtticEmulation

/// Tools › Import Steam Games: lists the Mac games installed through
/// Steam, asks before adding them, then gives each its Steam library
/// artwork and store info. After that, every library refresh keeps the
/// list in step with Steam (see `SteamLibrary.syncShortcuts`).
@MainActor
enum SteamImport {
    static var isSteamInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam") != nil
    }

    static func run(romsRoots: [URL], scanCoordinator: ScanCoordinator) async {
        guard let root = romsRoots.first else { return }
        let games = await Task.detached { SteamLibrary.installedGames() }.value
        guard !games.isEmpty else {
            let alert = NSAlert()
            alert.messageText = String(localized: "No Mac games installed through Steam")
            alert.informativeText = isSteamInstalled
                ? String(localized: "Install a game in Steam, then import again. Only games with a Mac version can be added.")
                : String(localized: "Steam isn't installed on this Mac.")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Import \(games.count) Steam games?")
        let names = games.prefix(12).map(\.title).joined(separator: ", ")
        alert.informativeText = (games.count > 12 ? names + "…" : names) + "\n\n"
            + String(localized: "These Mac games are installed through Steam. They'll play through Steam, and Attic adds or removes them as you install or uninstall them there.")
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let folder = root.appending(path: "steam", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        RemovedSystems.addBack(.steam)
        // The scan writes the shortcuts, then adds them.
        await scanCoordinator.scan(romsRootURLs: romsRoots, only: [.steam])
        AppLog.post(.info, "Imported \(games.count) Steam games.")
        await fetchArtwork(in: folder, scanCoordinator: scanCoordinator)
    }

    /// Store info, library artwork and a trailer for each Steam game
    /// missing any, from the Steam store, then SteamGridDB (with an API
    /// key) for the pictures the store doesn't have. Running the import
    /// again fills in what's still missing, and replaces logos at the
    /// store's small size.
    static func fetchArtwork(in folder: URL, scanCoordinator: ScanCoordinator) async {
        let kinds: [MediaKind] = [.covers, .fanart, .logos, .screenshots, .videos]
        let gridKey = SteamGridDBCredentialsStore().trimmedKey
        let shortcuts = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == SteamLibrary.shortcutExtension }
        let wanted = shortcuts.map { shortcut in
            (shortcut, kinds.filter { kind in
                let existing = MediaFolder.existingFiles(base: base(shortcut, in: folder, kind: kind))
                // A logo at the store's small size, 640 by 360: a sharper
                // one, once there is one.
                if kind == .logos, let logo = existing.first,
                   let size = MediaQuality.size(ofImage: logo), max(size.width, size.height) <= Self.storeLogoWidth {
                    return true
                }
                return existing.isEmpty
            })
        }.filter { !$0.1.isEmpty }
        guard !wanted.isEmpty else { return }

        let imported = await Task.detached {
            var imported: [String: LibraryStore.ImportedInfo] = [:]
            for (shortcut, missing) in wanted {
                guard let appID = SteamLibrary.appID(shortcut: shortcut) else { continue }
                let info = await SteamStore.info(appID: appID, fetch: download)
                let name = shortcut.lastPathComponent
                /// The first of `urls` that downloads, stored as the game's `kind`.
                func store(_ kind: MediaKind, _ urls: [URL?]) async -> String? {
                    guard missing.contains(kind) else { return nil }
                    for case let url? in urls {
                        guard let data = try? await download(url) else { continue }
                        return try? MediaFolder.store(data, fileExtension: url.pathExtension, forSystemFolder: folder,
                                                      romRelativePath: name, kind: kind).path
                    }
                    return nil
                }
                /// SteamGridDB's picture, only asked for when it's needed.
                func grid(_ art: SteamGridDB.Art, for kind: MediaKind) async -> URL? {
                    guard let gridKey, missing.contains(kind) else { return nil }
                    return await SteamGridDB.url(of: art, appID: appID, apiKey: gridKey, fetch: request)
                }
                // Without a library cover, the store only has a wide header:
                // a portrait cover from SteamGridDB comes before it.
                let hasPortrait = info.coverURL?.lastPathComponent.hasPrefix("library_") == true
                let cover = hasPortrait
                    ? await store(.covers, [info.coverURL])
                    : await store(.covers, [await grid(.cover, for: .covers), info.coverURL])
                let screenshot = await store(.screenshots, [info.screenshotURL])
                if await store(.fanart, [info.heroURL]) == nil {
                    _ = await store(.fanart, [await grid(.hero, for: .fanart)])
                }
                // The library's own logo, else SteamGridDB's best-rated,
                // else the small classic one.
                _ = await store(.logos, [info.logoURL, await grid(.logo, for: .logos), SteamStore.classicLogoURL(appID: appID)])
                var video: String?
                if missing.contains(.videos), let trailer = info.trailerURL {
                    let destination = base(shortcut, in: folder, kind: .videos).appendingPathExtension("mp4")
                    try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if (try? await SteamTrailer.save(master: trailer, to: destination, fetch: download)) != nil {
                        video = destination.path
                    }
                }
                imported[shortcut.path] = LibraryStore.ImportedInfo(
                    description: info.description, developer: info.developer, publisher: info.publisher,
                    genre: info.genre, releaseDate: info.releaseDate, coverPath: cover, screenshotPath: screenshot,
                    videoPath: video
                )
            }
            return imported
        }.value
        let changed = await scanCoordinator.applyImported(imported, replacing: false)
        AppLog.post(.info, "Added Steam artwork and info for \(changed) games.")
    }

    /// The width of the store's library logos.
    private nonisolated static let storeLogoWidth: CGFloat = 640

    private nonisolated static func base(_ shortcut: URL, in folder: URL, kind: MediaKind) -> URL {
        MediaFolder.baseURL(forSystemFolder: folder, romRelativePath: shortcut.lastPathComponent, kind: kind)
    }

    private nonisolated static func download(_ url: URL) async throws -> Data {
        try await request(URLRequest(url: url))
    }

    private nonisolated static func request(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
