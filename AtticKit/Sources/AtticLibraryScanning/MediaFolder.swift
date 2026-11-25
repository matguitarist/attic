import Foundation
import AtticModels
import PictureKit

/// The kinds of media Attic keeps, each in a folder of its own. The tree
/// is Attic's: other front-ends' names are read when bringing media in
/// (`ImportedMedia`), and the few Attic once shared with ES-DE but has
/// since renamed are moved on launch (`renamedKinds`). (ES-DE's mix images
/// and title screens aren't among them: Attic shows the box and a
/// screenshot instead.)
///
/// `covers` holds the 2D box art, in `2dboxes`, beside `3dboxes`, a
/// rendered 3D box (ScreenScraper's box-3D). `physicalMedia` holds the
/// game's cartridge, disc or board (see `PhysicalMedium`). `logos` holds
/// each game's logo, its title on a transparent background (ScreenScraper's
/// wheel, TheGamesDB's clear logo). `marquees` holds an arcade cabinet's
/// lit header, which RetroBat and Batocera file logos under, so theirs come
/// in as logos. `fanart` is a wide piece of art for behind the game.
/// `bezels` frames the game's picture, the way RetroArch overlays do.
public enum MediaKind: String, CaseIterable, Sendable {
    case covers = "2dboxes"
    case boxes3D = "3dboxes"
    case physicalMedia = "physicalmedia"
    case screenshots, videos, manuals, logos, marquees, fanart, bezels

    /// Stored as HEIC when that's smaller, which keeps a logo's
    /// transparency. Screenshots stay as they are, since compressing
    /// pixel art blurs it, and bezels as PNGs, which overlays need.
    public var isStoredAsHEIC: Bool {
        [.covers, .boxes3D, .physicalMedia, .logos, .marquees, .fanart].contains(self)
    }

    /// How a picture of this kind is stored: artwork as HEIC when that's
    /// smaller, scaled down to `maxPixelSize` when it's given. Nil keeps
    /// it as it is.
    public func pictureStyle(maxPixelSize: Int? = nil) -> PictureStyle? {
        isStoredAsHEIC ? PictureStyle.artwork.withLongSide(maxPixelSize) : nil
    }

    /// Folders Attic named differently before, by the kind they hold.
    public static let renamedKinds: [String: MediaKind] = ["covers": .covers]
}

/// Where a game's media lives: one tree next to the ROMs folder, in
/// ES-DE's layout, named after the ROM file.
///
///     Emulation/
///       ROMs/snes/Super Mario World (USA).sfc
///       Media/snes/2dboxes/Super Mario World (USA).heic
///
/// Attic's scraper, picked covers and the tidy-up all write here, and the
/// scanner reads from here (see `ESDEMediaResolver`).
public enum MediaFolder {
    public static let folderName = EmulationLayout.media
    /// Most compact first, which is also the order new files are written in.
    public static let imageExtensions = ["heic", "webp", "png", "jpg", "jpeg"]
    public static let videoExtensions = ["mp4", "mkv", "avi", "mov", "wmv"]

    /// A file's size, 0 when it can't be read.
    public static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// `<shared parent>/Media/<system folder name>` for a
    /// system's ROMs folder such as `Emulation/ROMs/snes`.
    /// Makes the media folders for each system folder in the ROMs folders:
    /// one per kind, ready for files copied in by hand. A system without a
    /// physical medium gets no `physicalmedia`. Folders made before
    /// (`created`, "<system>/<kind>") aren't made again, so one the user
    /// deletes stays deleted; the new ones are returned.
    public static func createFolders(romsRoots: [URL], created: Set<String>) -> Set<String> {
        let fileManager = FileManager.default
        var made: Set<String> = []
        for root in romsRoots {
            let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard let system = SystemTaxonomy.system(forShortName: folder.lastPathComponent)?.canonicalID else { continue }
                for kind in kinds(for: system) {
                    let key = "\(folder.lastPathComponent)/\(kind.rawValue)"
                    guard !created.contains(key) else { continue }
                    let url = self.root(forSystemFolder: folder).appending(path: kind.rawValue, directoryHint: .isDirectory)
                    if (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil { made.insert(key) }
                }
            }
        }
        return made
    }

    /// The kinds a system's games can have: marquees are arcade
    /// cabinets', and a cartridge or disc needs a system that had one.
    public static func kinds(for system: CanonicalSystemID) -> [MediaKind] {
        MediaKind.allCases.filter { kind in
            switch kind {
            case .physicalMedia: PhysicalMedium.of(system) != nil
            case .marquees: SystemTaxonomy.definition(for: system)?.category == .arcade
            default: true
            }
        }
    }

    /// Moves the folders of kinds Attic has renamed (`covers` to
    /// `2dboxes`) in the media folder beside each ROMs folder, into one
    /// already there if need be. Returns the old and new folders, for the
    /// library's paths to follow.
    public static func adoptRenamedKinds(romsRoots: [URL]) -> [(from: URL, to: URL)] {
        let fileManager = FileManager.default
        var renamed: [(URL, URL)] = []
        let mediaRoots = Set(romsRoots.map { $0.deletingLastPathComponent().appending(path: folderName, directoryHint: .isDirectory) })
        for mediaRoot in mediaRoots {
            for system in (try? fileManager.contentsOfDirectory(at: mediaRoot, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
                for (old, kind) in MediaKind.renamedKinds {
                    let from = system.appending(path: old, directoryHint: .isDirectory)
                    let to = system.appending(path: kind.rawValue, directoryHint: .isDirectory)
                    guard fileManager.fileExists(atPath: from.path) else { continue }
                    // An empty one made since is in the way of a rename.
                    if ((try? fileManager.contentsOfDirectory(atPath: to.path)) ?? []).filter({ $0 != ".DS_Store" }).isEmpty {
                        try? fileManager.removeItem(at: to)
                    }
                    if !fileManager.fileExists(atPath: to.path) {
                        if (try? fileManager.moveItem(at: from, to: to)) != nil { renamed.append((from, to)) }
                        continue
                    }
                    // Both there: what the new one lacks moves over.
                    for name in (try? fileManager.contentsOfDirectory(atPath: from.path)) ?? [] where name != ".DS_Store" {
                        let destination = to.appending(path: name)
                        if !fileManager.fileExists(atPath: destination.path) {
                            try? fileManager.moveItem(at: from.appending(path: name), to: destination)
                        }
                    }
                    renamed.append((from, to))
                    if ((try? fileManager.contentsOfDirectory(atPath: from.path)) ?? []).filter({ $0 != ".DS_Store" }).isEmpty {
                        try? fileManager.removeItem(at: from)
                    }
                }
            }
        }
        return renamed
    }

    public static func root(forSystemFolder systemFolder: URL) -> URL {
        systemFolder
            .deletingLastPathComponent() // ROMs
            .deletingLastPathComponent() // Emulation
            .appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: systemFolder.lastPathComponent, directoryHint: .isDirectory)
    }

    /// The system's own pictures, beside the kind folders in its media,
    /// named `system-<art>` with any image extension.
    ///
    ///     Media/snes/system-logo.png
    ///     Media/snes/system-fanart.jpg
    ///     Media/snes/system-picture.heic
    ///     Media/snes/system-video.mp4
    public enum SystemArt: String, CaseIterable, Sendable {
        /// In place of Attic's logo.
        case logo = "system-logo"
        /// A wallpaper for behind the system.
        case fanart = "system-fanart"
        /// The console itself.
        case picture = "system-picture"
        /// A trailer, played where the picture is.
        case video = "system-video"
    }

    /// The system's own `art`, if there's one.
    public static func systemArt(_ art: SystemArt, forSystemFolder systemFolder: URL) -> URL? {
        existingFiles(base: root(forSystemFolder: systemFolder).appending(path: art.rawValue)).first
    }

    /// Copies `picture` in as the system's `art`, replacing any earlier one
    /// (which goes to the Trash); nil removes it.
    @discardableResult
    public static func setSystemArt(_ art: SystemArt, to picture: URL?, forSystemFolder systemFolder: URL) throws -> URL? {
        let base = root(forSystemFolder: systemFolder).appending(path: art.rawValue)
        for existing in existingFiles(base: base) where existing != picture {
            try? FileManager.default.trashItem(at: existing, resultingItemURL: nil)
        }
        guard let picture else { return nil }
        guard base.appendingPathExtension(picture.pathExtension.lowercased()) != picture else { return picture }
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try copyPicture(picture, toBase: base)
    }

    /// Copies `picture` to `base` plus an extension, as HEIC when that's
    /// smaller (a 6 MB artwork PNG comes in at a tenth of it, transparency
    /// kept); anything that isn't a picture, such as a video, as it is.
    public static func copyPicture(_ picture: URL, toBase base: URL) throws -> URL {
        try PictureFile.copy(picture, to: base, style: .artwork, replaced: .trash)
    }

    /// The file for one game, before its extension: subfolders in the ROM's
    /// path are kept, the way ES-DE does.
    public static func baseURL(forSystemFolder systemFolder: URL, romRelativePath: String, kind: MediaKind) -> URL {
        root(forSystemFolder: systemFolder)
            .appending(path: kind.rawValue, directoryHint: .isDirectory)
            .appending(path: (romRelativePath as NSString).deletingPathExtension)
    }

    /// Puts `data` in place as the game's `kind`, replacing any earlier one
    /// whatever its type (which goes to the Trash). Covers and fan art are
    /// stored as HEIC when that's smaller (see `MediaKind.isStoredAsHEIC`),
    /// scaled down to `maxPixelSize` when it's given.
    public static func store(_ data: Data, fileExtension: String, forSystemFolder systemFolder: URL, romRelativePath: String,
                             kind: MediaKind, maxPixelSize: Int? = nil) throws -> URL {
        let base = baseURL(forSystemFolder: systemFolder, romRelativePath: romRelativePath, kind: kind)
        if let style = kind.pictureStyle(maxPixelSize: maxPixelSize),
           let stored = try? PictureFile.store(data, at: base, style: style, replaced: .trash) {
            return stored
        }
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        for existing in existingFiles(base: base) {
            try? FileManager.default.trashItem(at: existing, resultingItemURL: nil)
        }
        let ext = fileExtension.isEmpty ? (kind == .videos ? "mp4" : "png") : fileExtension.lowercased()
        let destination = base.appendingPathExtension(ext)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Files already there for `base`, in any image or video type.
    public static func existingFiles(base: URL) -> [URL] {
        (imageExtensions + videoExtensions).map { base.appendingPathExtension($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
