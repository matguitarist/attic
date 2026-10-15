import Foundation
import AtticModels

/// Finds the media and gamelist that came with games being added from
/// somewhere else — whatever front-end or scraper laid them out — so they
/// follow the games into Attic's own layout (see `MediaFolder`).
public enum ImportedMedia {
    /// Media folder names other apps use, by the kind they hold. Files
    /// inside are named after the game (`Game.png`), or Batocera-style
    /// (`Game-boxart.png`, see `MediaTidier.inFolderSuffixes`) in `images`.
    /// A `marquees` folder isn't taken for logos: MAME's hold the cabinets'
    /// real marquees.
    static let folderKinds: [String: MediaKind] = [
        "covers": .covers, "boxart": .covers, "box2dfront": .covers, "box - front": .covers, "boxes": .covers,
        "screenshots": .screenshots, "snap": .screenshots, "snaps": .screenshots, "screenshot - gameplay": .screenshots,
        "videos": .videos, "video": .videos, "snap videos": .videos,
        "manuals": .manuals, "manual": .manuals,
        "logos": .logos, "logo": .logos, "wheel": .logos, "clear logo": .logos,
        "fanart": .fanart, "fan art": .fanart, "fanart - background": .fanart, "backgrounds": .fanart,
    ]
    /// Folders that hold media or other apps' files, never games.
    public static let nonGameFolderNames: Set<String> = Set(folderKinds.keys)
        .union(["images", "media", "downloaded_images", "downloaded_media", "gamelists", "collections", "html_arrm",
                "marquees", "marquee", "3dboxes", "backcovers", "physicalmedia", "box3d", "support",
                "miximages", "mix", "mixrbv2", "titlescreens", "titles", "screenshot - game title",
                // A whole Batocera or ES-DE folder's other parts.
                "bios", "saves", "states", "themes", "music", "splash", "cheats", "decorations", "overlays", "shaders"])

    private static let imageExtensions: Set<String> = Set(MediaFolder.imageExtensions)
    private static let mediaExtensions: Set<String> = imageExtensions.union(MediaFolder.videoExtensions).union(["pdf"])

    /// Whether a file is media rather than a game (unless the system plays
    /// that type: PICO-8 carts are PNGs).
    public static func isMedia(_ url: URL, for system: CanonicalSystemID?) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard mediaExtensions.contains(ext) else { return false }
        return system.map { SystemROMExtensions.extensions(for: $0)?.contains(ext) != true } ?? true
    }

    /// The best file of each kind found for the game `rom`, looking next
    /// to it, in media folders beside it, in Batocera's `images` folder,
    /// and in a `Media` (or ES-DE `downloaded_media`) tree beside its ROMs
    /// folder.
    public static func media(forROM rom: URL, system: CanonicalSystemID?) -> [(file: URL, kind: MediaKind)] {
        let folder = rom.deletingLastPathComponent()
        let stem = rom.deletingPathExtension().lastPathComponent
        let mediaTrees = EmulationLayout.mediaNames.map {
            folder.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: $0).appending(path: folder.lastPathComponent)
        }
        let subfolders = children(of: folder).filter(isDirectory)

        var found: [MediaKind: URL] = [:]
        func offer(_ url: URL?, as kind: MediaKind) {
            if found[kind] == nil, let url { found[kind] = url }
        }
        for kind in MediaKind.allCases {
            let extensions = extensions(for: kind)
            // This app's own kind folders, then other names for them.
            for media in subfolders where folderKinds[media.lastPathComponent.lowercased()] == kind {
                offer(file(named: stem, in: media, extensions: extensions), as: kind)
            }
            for tree in mediaTrees {
                offer(file(named: stem, in: tree.appending(path: kind.rawValue), extensions: extensions), as: kind)
            }
        }
        // Batocera: images/Game-boxart.png, videos/Game-video.mp4…
        for (suffix, kind) in MediaTidier.inFolderSuffixes.sorted(by: { $0.key < $1.key }) {
            let batoceraFolder = folder.appending(path: kind == .videos ? "videos" : kind == .manuals ? "manuals" : "images")
            offer(file(named: "\(stem)-\(suffix)", in: batoceraFolder, extensions: extensions(for: kind)), as: kind)
        }
        offer(file(named: "\(stem)-thumb", in: folder.appending(path: "images"), extensions: Array(imageExtensions)), as: .covers)
        // An image beside the game, named like it, is its cover — unless
        // the system's games are images themselves.
        let gamesAreImages = system.flatMap { SystemROMExtensions.extensions(for: $0) }
            .map { !$0.isDisjoint(with: imageExtensions) } ?? false
        if !gamesAreImages {
            offer(file(named: stem, in: folder, extensions: MediaFolder.imageExtensions), as: .covers)
        }
        return MediaKind.allCases.compactMap { kind in found[kind].map { ($0, kind) } }
    }

    /// The gamelist that came with a folder of games: Batocera's, inside
    /// it, or ES-DE's, in a `Gamelists` (or `gamelists`) tree beside its
    /// ROMs folder.
    public static func gamelist(near folder: URL) -> URL? {
        let shared = folder.deletingLastPathComponent().deletingLastPathComponent()
        return ([folder.appending(path: "gamelist.xml")] + EmulationLayout.gamelistsNames.map {
            shared.appending(path: $0).appending(path: folder.lastPathComponent).appending(path: "gamelist.xml")
        })
        .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// `incoming` merged into the system's gamelist (`existing`, if it has
    /// one): without media paths, without games that aren't in
    /// `systemFolder`, and without games `existing` already describes.
    public static func mergedGamelist(_ incoming: String, into existing: String?, systemFolder: URL) -> String {
        let cleaned = MediaTidier.cleanedGamelist(incoming, systemFolder: systemFolder)
        guard let existing, let end = existing.range(of: "</gameList>", options: .backwards) else { return cleaned }
        let known = Set(paths(in: existing))
        let blocks = gameBlocks(in: cleaned).filter { block in
            paths(in: block).first.map { !known.contains($0) } ?? false
        }
        guard !blocks.isEmpty else { return existing }
        return existing.replacingCharacters(in: end.lowerBound..<end.lowerBound, with: blocks.joined())
    }

    // MARK: - Helpers

    private static func extensions(for kind: MediaKind) -> [String] {
        switch kind {
        case .videos: MediaFolder.videoExtensions
        case .manuals: ["pdf"]
        default: MediaFolder.imageExtensions
        }
    }

    private static func file(named name: String, in folder: URL, extensions: [String]) -> URL? {
        extensions.map { folder.appending(path: "\(name).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func gameBlocks(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "[ \\t]*<game\\b[^>]*>.*?</game>[ \\t]*\\r?\\n?", options: .dotMatchesLineSeparators)
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { nsText.substring(with: $0.range) }
    }

    private static func paths(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "<path>([^<]*)</path>")
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .map { ESDEGamelistMapper.normalizeRelativePath(nsText.substring(with: $0.range(at: 1))) }
    }

    private static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
