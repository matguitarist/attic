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
                        .aspectRatio(contentMode: .fit)
                        .padding(showBackground ? 8 : 0)
                } else {
                    placeholderGlyph
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
            .task(id: request) {
                guard let request, request.maxPixelSize > 0 else { return }
                if let image = await CoverArtThumbnailCache.shared.thumbnail(for: request.url, maxPixelSize: request.maxPixelSize),
                   !Task.isCancelled {
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
