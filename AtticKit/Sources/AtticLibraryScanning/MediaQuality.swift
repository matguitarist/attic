import Foundation
import ImageIO
import AVFoundation

/// How sharp a picture or video is, by its size in pixels, to tell a
/// low-quality file worth replacing from a good one.
public enum MediaQuality {
    /// A picture's size, read from its header without decoding it.
    public static func size(ofImage url: URL) -> CGSize? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(size)
    }

    public static func size(ofImageData data: Data) -> CGSize? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(size)
    }

    private static func size(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    /// A video's picture size, turned the way it plays.
    public static func size(ofVideo url: URL) async -> CGSize? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let size = natural.applying(transform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    /// Whether a picture is small for its kind: fan art below full HD,
    /// covers, boxes and cartridges under 1000 pixels, logos under 600. Screenshots
    /// are as big as the console's screen, so never.
    public static func isLowQuality(image size: CGSize, kind: MediaKind) -> Bool {
        let longest = max(size.width, size.height)
        switch kind {
        case .fanart: return longest < 1920
        case .logos: return longest < 600
        case .covers, .boxes3D, .physicalMedia: return longest < 1000
        case .marquees: return longest < 1000
        case .screenshots, .videos, .manuals, .bezels: return false
        }
    }

    /// Below 480 lines, what EmuMovies' HQ videos have.
    public static func isLowQuality(video size: CGSize) -> Bool {
        min(size.width, size.height) < 480
    }

    /// Whether `new` is clearly sharper than `old`: a quarter more pixels,
    /// so a file isn't swapped for one barely different.
    public static func isBetter(_ new: CGSize, than old: CGSize) -> Bool {
        new.width * new.height > old.width * old.height * 1.25
    }
}
