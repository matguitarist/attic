import Foundation
import RomsBoxModels

/// ES-DE convention: `gamelist.xml` lives in a separate tree at
/// `<ES-DE root>/gamelists/<system>/gamelist.xml`, not inside the ROMs
/// folder itself (contrast `BatoceraLibraryImporter`, where it's colocated
/// with the ROMs). Media is matched purely by filename against
/// `<ES-DE root>/downloaded_media/<system>/<type>/`.
///
/// The ES-DE root is assumed to be the default sibling of the ROMs root
/// (`~/ROMs` and `~/ES-DE` side by side), matching ES-DE's out-of-the-box
/// install layout. A custom "ES-DE app data location" override is out of
/// MVP scope.
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
        systemFolderURL
            .deletingLastPathComponent() // ROMs root, e.g. ~/ROMs
            .deletingLastPathComponent() // shared parent, e.g. ~
            .appending(path: "ES-DE")
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
