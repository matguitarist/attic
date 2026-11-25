import SwiftUI
import PictureKitUI

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
///
/// Pictures are decoded by PictureKit's `PictureCache`. It isn't
/// `AsyncPicture`, which always centers: shelves stand 3D boxes on their
/// bottom edge and logos on their side (`alignment`).
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
    /// 0 for art that runs to a screen's edges, such as a marquee.
    var cornerRadius: CGFloat = 10

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: Loaded?

    /// Remembers which request produced the image, so a recycled cell
    /// showing a different game (or the same game at a new zoom level)
    /// never briefly renders the previous art.
    private struct Loaded {
        let request: Request
        let image: CGImage
    }

    private struct Request: Hashable {
        let source: PictureSource
        let pixels: Int
        /// Changes when the file is replaced at the same path.
        let revision: Int
    }

    var body: some View {
        GeometryReader { proxy in
            let request = url.map {
                Request(source: fills ? Self.trimmed($0) : .file($0),
                        pixels: PictureCache.step(Int((max(proxy.size.width, proxy.size.height) * displayScale).rounded(.up))),
                        revision: PictureRevisions.shared.revision(of: PictureSource.file($0).id))
            }

            ZStack {
                if showBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                guard let request, request.pixels > 0, image(for: request) == nil else { return }
                if let image = await PictureCache.shared.image(request.source, maxPixels: request.pixels), !Task.isCancelled {
                    loaded = Loaded(request: request, image: image)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Many screenshots come with black bars of their own, which a filled
    /// card would show as a smaller picture.
    nonisolated static func trimmed(_ url: URL) -> PictureSource {
        PictureSource.file(url).applying("trimmed") { $0.trimmingDarkBorders() }
    }

    /// Prefers whatever's already in the shared cache (so cells scrolling
    /// back into view render art on their first frame) over this view's
    /// own `@State`, which only fills in after the async load completes.
    private func image(for request: Request) -> CGImage? {
        if let loaded, loaded.request == request { return loaded.image }
        return PictureCache.shared.cached(request.source, maxPixels: request.pixels)
    }

    private var placeholderGlyph: some View {
        Text(title.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.secondary)
    }
}

extension PictureCache {
    /// Forgets a media file replaced or removed at the same path, as drawn
    /// and with its dark borders trimmed, so every view showing it loads
    /// it again.
    func forgetMedia(_ url: URL) {
        forget(.file(url))
        forget(GameCoverArtView.trimmed(url))
    }
}
