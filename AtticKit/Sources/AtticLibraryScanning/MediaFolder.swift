import Foundation
import CoreGraphics
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

    // MARK: - Manuals

    /// Written into manuals Attic recompressed (the PDF's Creator), so
    /// they're never done twice.
    static let manualCreator = "Attic"
    /// Set on a manual that didn't get smaller, for the same reason.
    static let checkedAttribute = "com.attic.manual-checked"
    /// Scans heavier than this per page are worth redoing: a typical
    /// cartridge-era manual is 50–80 KB a page, Neo Geo scans ten times more.
    static let heavyBytesPerPage = 150_000

    /// Whether a manual is a heavy scan Attic hasn't tried to shrink yet.
    public static func manualIsWorthCompressing(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "pdf",
              getxattr(url.path, checkedAttribute, nil, 0, 0, 0) < 0,
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0,
              creator(of: document) != manualCreator else { return false }
        return size / document.numberOfPages > heavyBytesPerPage
    }

    /// Redraws each page at 150 dpi as a JPEG, which keeps scanned text
    /// sharp at full screen. The new file replaces the old one (which goes
    /// to the Trash) only when it's at most 60% of its size. Returns
    /// whether it was replaced.
    @discardableResult
    public static func compressManual(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0,
              let original = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return false }
        let temporary = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).pdf")
        defer { try? fileManager.removeItem(at: temporary) }

        guard rewriteManual(document, to: temporary),
              let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              Double(size) <= Double(original) * 0.6,
              (try? fileManager.trashItem(at: url, resultingItemURL: nil)) != nil else {
            _ = setxattr(url.path, checkedAttribute, "1", 1, 0, 0)
            return false
        }
        return (try? fileManager.moveItem(at: temporary, to: url)) != nil
    }

    private static func rewriteManual(_ document: CGPDFDocument, to destination: URL) -> Bool {
        let info = [kCGPDFContextCreator: manualCreator] as CFDictionary
        guard let output = CGContext(destination as CFURL, mediaBox: nil, info),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let scale = 150.0 / 72
        for number in 1...document.numberOfPages {
            // Turned pages would need their rotation redone; leave those be.
            guard let page = document.page(at: number), page.rotationAngle == 0 else { return false }
            let box = page.getBoxRect(.mediaBox)
            let (width, height) = (Int(box.width * scale), Int(box.height * scale))
            guard width > 0, height > 0,
                  let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            bitmap.scaleBy(x: scale, y: scale)
            bitmap.translateBy(x: -box.minX, y: -box.minY)
            bitmap.drawPDFPage(page)

            let jpeg = NSMutableData()
            guard let rendered = bitmap.makeImage(),
                  let encoder = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
            CGImageDestinationAddImage(encoder, rendered, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
            guard CGImageDestinationFinalize(encoder),
                  let provider = CGDataProvider(data: jpeg),
                  let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return false }
            var pageBox = CGRect(origin: .zero, size: box.size)
            output.beginPage(mediaBox: &pageBox)
            output.draw(image, in: pageBox)
            output.endPage()
        }
        output.closePDF()
        return true
    }

    private static func creator(of document: CGPDFDocument) -> String? {
        var value: CGPDFStringRef?
        guard let info = document.info, CGPDFDictionaryGetString(info, "Creator", &value), let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }

}
