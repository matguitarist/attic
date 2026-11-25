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

    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.card)
            }
            AsyncPicture(url.map { fills ? Self.trimmed($0) : .file($0) }, contentMode: fills ? .fill : .fit, alignment: alignment) {
                placeholderGlyph
            }
            .padding(showBackground ? 8 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Many screenshots come with black bars of their own, which a filled
    /// card would show as a smaller picture.
    nonisolated static func trimmed(_ url: URL) -> PictureSource {
        PictureSource.file(url).applying("trimmed") { $0.trimmingDarkBorders() }
    }

    private var placeholderGlyph: some View {
        Text(title.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.secondary)
    }
}
