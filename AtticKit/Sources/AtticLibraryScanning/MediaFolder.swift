import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The kinds of media Attic keeps, named like ES-DE's folders so the same
/// tree still works there.
public enum MediaKind: String, CaseIterable, Sendable {
    case covers, miximages, screenshots, titlescreens, videos, manuals
}

/// Where a game's media lives: one tree next to the ROMs folder, in
/// ES-DE's layout, named after the ROM file.
///
///     Emulation/
///       ROMs/snes/Super Mario World (USA).sfc
///       downloaded_media/snes/covers/Super Mario World (USA).heic
///
/// Attic's scraper, picked covers and the tidy-up all write here, and the
/// scanner reads from here (see `ESDEMediaResolver`).
public enum MediaFolder {
    public static let folderName = "downloaded_media"
    /// Most compact first, which is also the order new files are written in.
    public static let imageExtensions = ["heic", "webp", "png", "jpg", "jpeg"]
    public static let videoExtensions = ["mp4", "mkv", "avi", "mov", "wmv"]

    /// `<shared parent>/downloaded_media/<system folder name>` for a
    /// system's ROMs folder such as `Emulation/ROMs/snes`.
    public static func root(forSystemFolder systemFolder: URL) -> URL {
        systemFolder
            .deletingLastPathComponent() // ROMs
            .deletingLastPathComponent() // Emulation
            .appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: systemFolder.lastPathComponent, directoryHint: .isDirectory)
    }

    /// The file for one game, before its extension: subfolders in the ROM's
    /// path are kept, the way ES-DE does.
    public static func baseURL(forSystemFolder systemFolder: URL, romRelativePath: String, kind: MediaKind) -> URL {
        root(forSystemFolder: systemFolder)
            .appending(path: kind.rawValue, directoryHint: .isDirectory)
            .appending(path: (romRelativePath as NSString).deletingPathExtension)
    }

    /// Puts `data` in place as the game's `kind`, replacing any earlier one
    /// whatever its type (which goes to the Trash). Covers are stored as
    /// HEIC when that's smaller; screenshots stay as they are, since
    /// compressing pixel art blurs it.
    public static func store(_ data: Data, fileExtension: String, forSystemFolder systemFolder: URL, romRelativePath: String, kind: MediaKind) throws -> URL {
        let base = baseURL(forSystemFolder: systemFolder, romRelativePath: romRelativePath, kind: kind)
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        for existing in existingFiles(base: base) {
            try? FileManager.default.trashItem(at: existing, resultingItemURL: nil)
        }
        if kind == .covers, let heic = heicData(from: data) {
            let destination = base.appendingPathExtension("heic")
            try heic.write(to: destination, options: .atomic)
            return destination
        }
        let ext = fileExtension.isEmpty ? "png" : fileExtension.lowercased()
        let destination = base.appendingPathExtension(ext)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    /// Files already there for `base`, in any image or video type.
    public static func existingFiles(base: URL) -> [URL] {
        (imageExtensions + videoExtensions).map { base.appendingPathExtension($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - HEIC

    /// About 40% smaller than PNG for box art at no visible cost, and
    /// decoded in hardware. (macOS can read WebP but not write it.)
    /// Nil when it wouldn't be smaller or the image can't be read.
    public static func heicData(from data: Data, quality: Double = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length < data.count else { return nil }
        return output as Data
    }

    /// Rewrites a PNG or JPEG as HEIC beside it, then moves the original to
    /// the Trash. Returns the new file, or nil when it was left as it was.
    @discardableResult
    public static func compressToHEIC(_ url: URL) -> URL? {
        guard ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
              let data = try? Data(contentsOf: url),
              let heic = heicData(from: data) else { return nil }
        let destination = url.deletingPathExtension().appendingPathExtension("heic")
        guard !FileManager.default.fileExists(atPath: destination.path),
              (try? heic.write(to: destination, options: .atomic)) != nil else { return nil }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        return destination
    }
}
