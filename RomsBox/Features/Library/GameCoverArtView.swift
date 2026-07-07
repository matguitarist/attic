import SwiftUI

/// Renders a game's cover art with a graceful placeholder fallback — used
/// by both the grid and the detail pane so a missing/undecodable art file
/// never surfaces as a broken image.
struct GameCoverArtView: View {
    let url: URL?
    let title: String

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.15))
            Text(title.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}
