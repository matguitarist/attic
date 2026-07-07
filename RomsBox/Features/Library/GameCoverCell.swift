import SwiftUI
import RomsBoxPersistence

struct GameCoverCell: View {
    let game: Game
    let isSelected: Bool

    /// Fixed art aspect + fixed title height + fixed overall width give
    /// every cell an identical footprint regardless of art or title
    /// content, so rows and columns line up exactly.
    private static let width: CGFloat = 160
    private static let artAspectRatio: CGFloat = 3.0 / 4.0
    private static let titleHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 6) {
            GameCoverArtView(url: game.coverArtURL, title: game.title)
                .frame(width: Self.width, height: Self.width / Self.artAspectRatio)
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
            .frame(width: Self.width, height: Self.titleHeight)
        }
        .frame(width: Self.width)
        .contentShape(Rectangle())
    }
}
