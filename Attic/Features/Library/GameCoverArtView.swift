import SwiftUI

/// Renders a game's cover art with a graceful placeholder fallback — used
/// by both the grid and the detail pane so a missing/undecodable art file
/// never surfaces as a broken image.
///
/// Real box art proportions vary wildly by system (confirmed against the
/// real library: NES covers are portrait ~0.73, SNES ~1.36 — landscape —
/// and GBA is nearly square ~1.0), so this always fits the whole image
/// without cropping, on a fixed card background — the caller supplies a
/// fixed frame, and art of any shape sits centered on a uniform "card"
/// instead of being cropped to force one aspect ratio.
struct GameCoverArtView: View {
    let url: URL?
    let title: String
    /// Grid cells keep the filler card (`true`) so every cell has the same
    /// uniform "box" footprint regardless of art shape. The detail panel
    /// turns it off for a cleaner look now that the art is shown bigger
    /// and centered on its own, where a visible card edge around
    /// differently-shaped art reads as clutter rather than alignment.
    var showBackground: Bool = true
    /// Where art narrower than the frame sits, such as a wide logo.
    var alignment: Alignment = .center
    /// Fills the frame, cropping, instead of fitting inside it: wide cards.
    var fills = false

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: LoadedImage?

    /// Remembers which request produced the image, so a recycled cell
    /// showing a different game (or the same game at a new zoom level)
    /// never briefly renders the previous art.
    private struct LoadedImage {
        let request: ThumbnailRequest
        let image: CGImage
    }

    private struct ThumbnailRequest: Hashable {
        let url: URL
        let maxPixelSize: CGFloat
        /// Changes when the file is replaced at the same path.
        let revision: Int
    }

    var body: some View {
        GeometryReader { proxy in
            let request = url.map {
                ThumbnailRequest(url: $0, maxPixelSize: max(proxy.size.width, proxy.size.height) * displayScale,
                                 revision: MediaRevisions.shared.revision(of: $0))
            }

            ZStack {
                if showBackground {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.card)
                }

                if let request, let image = image(for: request) {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .aspectRatio(contentMode: fills ? .fill : .fit)
                        .padding(showBackground ? 8 : 0)
                } else {
                    placeholderGlyph
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
            .task(id: request) {
                guard let request, request.maxPixelSize > 0 else { return }
                if var image = await CoverArtThumbnailCache.shared.thumbnail(for: request.url, maxPixelSize: request.maxPixelSize),
                   !Task.isCancelled {
                    // Many screenshots come with black bars of their own,
                    // which a filled card would show as a smaller picture.
                    if fills {
                        let untrimmed = image
                        image = await Task.detached(priority: .userInitiated) { untrimmed.trimmingDarkBorders() }.value
                    }
                    loadedImage = LoadedImage(request: request, image: image)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Prefers whatever's already in the shared cache (so cells scrolling
    /// back into view render art on their first frame) over this view's
    /// own `@State`, which only fills in after the async load completes.
    private func image(for request: ThumbnailRequest) -> CGImage? {
        if let loadedImage, loadedImage.request == request {
            return loadedImage.image
        }
        return CoverArtThumbnailCache.shared.cachedThumbnail(for: request.url, maxPixelSize: request.maxPixelSize)
    }

    private var placeholderGlyph: some View {
        Text(title.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.secondary)
    }
}

extension CGImage {
    /// The picture without the dark bars along its edges — the black
    /// borders many screenshots are captured with — up to a fifth of it a
    /// side, so dark art itself isn't eaten. Itself when there are none.
    func trimmingDarkBorders() -> CGImage {
        let (w, h) = (width, height)
        guard w > 8, h > 8,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return self }
        context.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Rows are top first in the bitmap.
        func isDark(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return pixels[i] < 28 && pixels[i + 1] < 28 && pixels[i + 2] < 28
        }
        // A line counts as a bar when nearly all of it is dark, allowing a
        // stray pixel or two of noise.
        func columnIsBar(_ x: Int) -> Bool { (0..<h).count { isDark(x, $0) } >= h * 98 / 100 }
        func rowIsBar(_ y: Int) -> Bool { (0..<w).count { isDark($0, y) } >= w * 98 / 100 }

        var (left, right, top, bottom) = (0, w - 1, 0, h - 1)
        while left < w / 5, columnIsBar(left) { left += 1 }
        while right > w - 1 - w / 5, columnIsBar(right) { right -= 1 }
        while top < h / 5, rowIsBar(top) { top += 1 }
        while bottom > h - 1 - h / 5, rowIsBar(bottom) { bottom -= 1 }
        guard left > 0 || top > 0 || right < w - 1 || bottom < h - 1 else { return self }
        return cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) ?? self
    }
}
