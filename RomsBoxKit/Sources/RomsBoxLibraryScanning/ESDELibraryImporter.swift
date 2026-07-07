import Foundation
import RomsBoxModels

/// ES-DE convention: `gamelist.xml` lives in a separate tree at
/// `<root>/gamelists/<system>/gamelist.xml`, not inside the ROMs folder
/// itself (contrast `BatoceraLibraryImporter`, where it's colocated with
/// the ROMs). Media is matched purely by filename against
/// `<root>/downloaded_media/<system>/<type>/`.
///
/// Critically, the gamelists root and the downloaded_media root are
/// resolved **independently** — confirmed against a real library where
/// ROMs and downloaded_media both live under a customized `~/Emulation`
/// folder, while gamelists (never moved) stayed at ES-DE's untouched
/// default `~/ES-DE/gamelists`. Tying both to one shared "ES-DE root" (an
/// earlier version of this importer did) silently found the media but
/// missed all the real scraped metadata, since the two trees aren't
/// actually in the same place. Each is resolved by probing the same three
/// candidate roots — the packaged-default sibling of the ROMs root
/// (`~/ROMs` next to `~/ES-DE`), the flat layout where ROMs/downloaded_media/
/// gamelists all share one parent directly, and ES-DE's literal untouched
/// default `~/ES-DE` — independently picking whichever candidate actually
/// has a `<gamelists|downloaded_media>/<system>` subfolder for each concern.
public struct ESDELibraryImporter: LibraryImporter {
    /// Overridable so tests never depend on the real machine's actual home
    /// directory contents — on the machine this was developed on, `~/ES-DE`
    /// has real scraped data for most MVP system short names, which would
    /// otherwise make fixture-based tests pass or fail based on ambient
    /// state rather than the fixture actually being exercised.
    private let homeDirectoryURL: URL

    public init(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectoryURL = homeDirectoryURL
    }

    public func detect(systemFolderURL: URL) -> Bool {
        if gamelistURL(forSystemFolderURL: systemFolderURL) != nil {
            return true
        }
        if mediaRoot(forSystemFolderURL: systemFolderURL) != nil {
            return true
        }

        // No positive ES-DE signal, but also no Batocera signal (a colocated
        // gamelist.xml) — confirmed against a real ES-DE library where a
        // system folder can be entirely unscraped (no gamelist.xml or
        // downloaded_media exist anywhere for it yet) while still containing
        // real ROM files. ES-DE itself still lists those as bare, art-less
        // entries rather than hiding the system, so default to that instead
        // of silently dropping populated folders neither convention claims.
        let hasColocatedGamelist = FileManager.default.fileExists(
            atPath: systemFolderURL.appending(path: "gamelist.xml").path
        )
        return !hasColocatedGamelist && !Self.romFiles(in: systemFolderURL).isEmpty
    }

    public func importSystem(systemFolderURL: URL, canonicalID: CanonicalSystemID) throws -> ImportedSystemData {
        let systemName = systemFolderURL.lastPathComponent
        let resolvedMediaRoot = mediaRoot(forSystemFolderURL: systemFolderURL)
            ?? candidateRoots(forSystemFolderURL: systemFolderURL)[0]
        let mediaResolver = ESDEMediaResolver(esdeRoot: resolvedMediaRoot, systemName: systemName)

        var games: [ImportedGameRecord] = []
        if let gamelistURL = gamelistURL(forSystemFolderURL: systemFolderURL) {
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

    private func candidateRoots(forSystemFolderURL systemFolderURL: URL) -> [URL] {
        let sharedParent = systemFolderURL
            .deletingLastPathComponent() // ROMs root, e.g. ~/ROMs or ~/Emulation/ROMs
            .deletingLastPathComponent() // shared parent, e.g. ~ or ~/Emulation

        return [
            sharedParent.appending(path: "ES-DE"), // packaged default: ~/ES-DE next to ~/ROMs
            sharedParent, // flat layout: ~/Emulation/{ROMs,downloaded_media,gamelists}
            homeDirectoryURL.appending(path: "ES-DE") // ES-DE's untouched default
        ]
    }

    /// First candidate root with a `gamelists/<system>/gamelist.xml`.
    private func gamelistURL(forSystemFolderURL systemFolderURL: URL) -> URL? {
        let systemName = systemFolderURL.lastPathComponent
        for root in candidateRoots(forSystemFolderURL: systemFolderURL) {
            let url = root.appending(path: "gamelists").appending(path: systemName).appending(path: "gamelist.xml")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// First candidate root with a `downloaded_media/<system>` folder,
    /// resolved independently of `gamelistURL` since the two don't have to
    /// live in the same place.
    private func mediaRoot(forSystemFolderURL systemFolderURL: URL) -> URL? {
        let systemName = systemFolderURL.lastPathComponent
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        for root in candidateRoots(forSystemFolderURL: systemFolderURL) {
            let mediaDir = root.appending(path: "downloaded_media").appending(path: systemName)
            if fm.fileExists(atPath: mediaDir.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return root
            }
        }
        return nil
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
            // ES-DE auto-generates this per-system metadata file (supported
            // extensions, launch command templates) — not a ROM.
            if url.lastPathComponent.caseInsensitiveCompare("systeminfo.txt") == .orderedSame { return nil }
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
