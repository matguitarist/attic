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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.4))

            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        placeholderGlyph
                    }
                }
            } else {
                placeholderGlyph
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholderGlyph: some View {
        Text(title.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.secondary)
    }
}
