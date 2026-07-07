import SwiftUI
import RomsBoxPersistence

struct GameCoverCell: View {
    let game: Game
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            GameCoverArtView(url: game.coverArtURL, title: game.title)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }

            HStack(spacing: 4) {
                Text(game.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if game.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .frame(height: 32)
        }
        .contentShape(Rectangle())
    }
}
