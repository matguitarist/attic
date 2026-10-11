import Foundation
import ImageIO

/// Decodes box art at roughly the size it's actually displayed and keeps
/// the results in memory. `AsyncImage` on a local file decoded the full
/// source image (often 1000+ px scans) every time a grid cell scrolled back
/// into view, with no caching at all — fine for a dozen games, janky for a
/// few thousand.
///
/// Thumbnails are produced with ImageIO's downsampling path, which never
/// materializes the full-resolution bitmap, and requested sizes are
/// bucketed so dragging the zoom slider doesn't create a separate cache
/// entry for every intermediate pixel width.
final class CoverArtThumbnailCache: @unchecked Sendable {
    static let shared = CoverArtThumbnailCache()

    private static let sizeBucket = 256

    // NSCache is internally thread-safe; it just isn't annotated Sendable.
    private let cache: NSCache<NSString, CGImage>

    init(totalCostLimitBytes: Int = 256 * 1024 * 1024) {
        cache = NSCache()
        cache.totalCostLimit = totalCostLimitBytes
    }

    /// Synchronous lookup so a cell scrolling back into view can render its
    /// art on the very first frame instead of flashing the placeholder.
    func cachedThumbnail(for url: URL, maxPixelSize: CGFloat) -> CGImage? {
        cache.object(forKey: key(for: url, bucketedSize: Self.bucketed(maxPixelSize)))
    }

    func thumbnail(for url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        let size = Self.bucketed(maxPixelSize)
        let key = key(for: url, bucketedSize: size)
        if let hit = cache.object(forKey: key) { return hit }

        let image = await Task.detached(priority: .userInitiated) {
            Self.decodeThumbnail(at: url, maxPixelSize: size)
        }.value

        if let image {
            cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    /// Scrapes can overwrite art in place at the same path (a forced
    /// re-scrape writes to the same `<rom>.png`), which would otherwise keep
    /// serving the old image until relaunch.
    func invalidate(_ url: URL) {
        // NSCache can't enumerate keys, so evict every bucket this URL could
        // plausibly have been cached under.
        for multiple in 1...8 {
            cache.removeObject(forKey: key(for: url, bucketedSize: multiple * Self.sizeBucket))
        }
    }

    private func key(for url: URL, bucketedSize: Int) -> NSString {
        "\(bucketedSize)|\(url.path)" as NSString
    }

    private static func bucketed(_ pixelSize: CGFloat) -> Int {
        let rounded = Int(pixelSize.rounded(.up))
        return max(sizeBucket, (rounded + sizeBucket - 1) / sizeBucket * sizeBucket)
    }

    private static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
