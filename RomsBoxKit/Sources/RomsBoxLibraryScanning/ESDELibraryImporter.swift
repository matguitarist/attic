import Foundation
import RomsBoxModels

/// ES-DE convention: `gamelist.xml` lives in a separate tree at
/// `<ES-DE root>/gamelists/<system>/gamelist.xml`, not inside the ROMs
/// folder itself (contrast `BatoceraLibraryImporter`, where it's colocated
/// with the ROMs). Media is matched purely by filename against
/// `<ES-DE root>/downloaded_media/<system>/<type>/`.
///
/// The ES-DE root is located by probing two real-world layouts against the
/// ROMs root's parent directory: ES-DE's packaged-default sibling folder
/// (`~/ROMs` and `~/ES-DE` side by side), and the equally common setup where
/// a user points ES-DE's "app data directory" *at* the same parent that
/// holds `ROMs/` directly (e.g. `~/Emulation/{ROMs,downloaded_media,
/// gamelists}` with no extra `ES-DE/` path component) — confirmed against a
/// real ES-DE library that uses the latter. A fully independent custom
/// location unrelated to the ROMs root's parent is out of MVP scope.
public struct ESDELibraryImporter: LibraryImporter {
    public init() {}

    public func detect(systemFolderURL: URL) -> Bool {
        let systemName = systemFolderURL.lastPathComponent
        let esdeRoot = Self.esdeRootURL(forSystemFolderURL: systemFolderURL)

        if FileManager.default.fileExists(atPath: Self.gamelistURL(esdeRoot: esdeRoot, systemName: systemName).path) {
            return true
        }

        var isDirectory: ObjCBool = false
        let mediaDir = esdeRoot.appending(path: "downloaded_media").appending(path: systemName)
        return FileManager.default.fileExists(atPath: mediaDir.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public func importSystem(systemFolderURL: URL, canonicalID: CanonicalSystemID) throws -> ImportedSystemData {
        let systemName = systemFolderURL.lastPathComponent
        let esdeRoot = Self.esdeRootURL(forSystemFolderURL: systemFolderURL)
        let mediaResolver = ESDEMediaResolver(esdeRoot: esdeRoot, systemName: systemName)
        let gamelistURL = Self.gamelistURL(esdeRoot: esdeRoot, systemName: systemName)

        var games: [ImportedGameRecord] = []
        if FileManager.default.fileExists(atPath: gamelistURL.path) {
            let data = try Data(contentsOf: gamelistURL)
            games = try ESDEGamelistMapper.parse(data, mediaResolver: mediaResolver)
        }

        // Fall back to bare ROM-file discovery for anything not covered by
        // gamelist.xml — not yet scraped, or scraped only partially.
        let knownPaths = Set(games.map(\.romRelativePath))
        for romPath in Self.romFiles(in: systemFolderURL) where !knownPaths.contains(romPath) {
            games.append(Self.bareGameRecord(romRelativePath: romPath, mediaResolver: mediaResolver))
        }

        return ImportedSystemData(
            canonicalID: canonicalID,
            libraryFormat: .esde,
            romsRootURL: systemFolderURL,
            games: games
        )
    }

    static func esdeRootURL(forSystemFolderURL systemFolderURL: URL) -> URL {
        let sharedParent = systemFolderURL
            .deletingLastPathComponent() // ROMs root, e.g. ~/ROMs or ~/Emulation/ROMs
            .deletingLastPathComponent() // shared parent, e.g. ~ or ~/Emulation

        let candidates = [
            sharedParent.appending(path: "ES-DE"), // packaged default: ~/ES-DE next to ~/ROMs
            sharedParent // flat layout: ~/Emulation/{ROMs,downloaded_media,gamelists}
        ]
        return candidates.first(where: looksLikeESDERoot) ?? candidates[0]
    }

    private static func looksLikeESDERoot(_ root: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        for name in ["downloaded_media", "gamelists"] {
            if fm.fileExists(atPath: root.appending(path: name).path, isDirectory: &isDirectory), isDirectory.boolValue {
                return true
            }
        }
        return false
    }

    private static func gamelistURL(esdeRoot: URL, systemName: String) -> URL {
        esdeRoot.appending(path: "gamelists").appending(path: systemName).appending(path: "gamelist.xml")
    }

    private static func romFiles(in systemFolderURL: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: systemFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }
        return entries.compactMap { url -> String? in
            if url.lastPathComponent.hasPrefix(".") { return nil }
            if url.lastPathComponent == "gamelist.xml" { return nil }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isDirectory ? nil : url.lastPathComponent
        }.sorted()
    }

    private static func bareGameRecord(romRelativePath: String, mediaResolver: ESDEMediaResolver) -> ImportedGameRecord {
        let nameNoExt = (romRelativePath as NSString).deletingPathExtension
        return ImportedGameRecord(
            romRelativePath: romRelativePath,
            title: nameNoExt,
            coverArtURL: mediaResolver.resolveCoverArt(romNameNoExt: nameNoExt),
            titleScreenURL: mediaResolver.resolveTitleScreen(romNameNoExt: nameNoExt),
            videoURL: mediaResolver.resolveVideo(romNameNoExt: nameNoExt)
        )
    }
}
