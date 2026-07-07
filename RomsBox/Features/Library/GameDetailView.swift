import SwiftUI
import RomsBoxPersistence

struct GameDetailView: View {
    let game: Game?

    var body: some View {
        if let game {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GameCoverArtView(url: game.coverArtURL, title: game.title)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .frame(maxWidth: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(game.title)
                        .font(.title2.bold())

                    HStack {
                        Button {
                            game.favorite.toggle()
                        } label: {
                            Label(game.favorite ? "Favorited" : "Favorite", systemImage: game.favorite ? "star.fill" : "star")
                        }

                        Button {
                            // Wired to RetroArch / custom emulator launching in Phase 7-8.
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                        .help("Launching a game arrives in Phase 7")
                    }

                    if let description = game.gameDescription, !description.isEmpty {
                        Text(description)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        detailRow("Developer", game.developer)
                        detailRow("Publisher", game.publisher)
                        detailRow("Genre", game.genre)
                        detailRow("Players", game.players)
                        if let releaseDate = game.releaseDate {
                            detailRow("Released", releaseDate.formatted(date: .abbreviated, time: .omitted))
                        }
                        if game.playCount > 0 {
                            detailRow("Play Count", "\(game.playCount)")
                        }
                        if let lastPlayed = game.lastPlayedDate {
                            detailRow("Last Played", lastPlayed.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .font(.callout)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No Game Selected",
                systemImage: "gamecontroller",
                description: Text("Select a game to see its details.")
            )
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value)
            }
        }
    }
}
