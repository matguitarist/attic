import SwiftUI
import AtticPersistence

struct GameCoverCell: View {
    let game: Game
    let isSelected: Bool
    let width: CGFloat

    /// Fixed art aspect + fixed title height give every cell an identical
    /// footprint regardless of art or title content, so rows and columns
    /// line up exactly — `width` itself is driven by the grid's zoom slider.
    private static let artAspectRatio: CGFloat = 3.0 / 4.0
    private static let titleHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 6) {
            GameCoverArtView(url: game.coverArtURL, title: game.title)
                .frame(width: width, height: width / Self.artAspectRatio)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }

            HStack(spacing: 4) {
                Text(game.title)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                if game.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .frame(width: width, height: Self.titleHeight)
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}
