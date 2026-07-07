import SwiftUI
import RomsBoxPersistence
import RomsBoxEmulation

struct GameDetailView: View {
    let game: Game?

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore

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

                        playButton(for: game)
                    }

                    if case .failed(let message) = launchCoordinator.state {
                        Text(message).foregroundStyle(.red).font(.callout)
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
    private func playButton(for game: Game) -> some View {
        let core = resolvedCore(for: game)
        let isRunningThisGame = launchCoordinator.state == .running(gameID: game.persistentModelID)
        let isBusy = launchCoordinator.state == .launching || isRunningThisGame

        Button {
            guard let core else { return }
            launchCoordinator.playWithRetroArch(game: game, core: core, retroArchBinaryURL: retroArchStore.binaryURL)
        } label: {
            Label(isRunningThisGame ? "Running…" : "Play", systemImage: isRunningThisGame ? "gamecontroller.fill" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(core == nil || isBusy)
        .help(core == nil ? "Set a default RetroArch core for this system in Settings \u{2192} RetroArch" : "")
    }

    private func resolvedCore(for game: Game) -> RetroArchCoreInfo? {
        guard case .retroArchCore(let identifier) = game.system?.defaultLaunchTarget else { return nil }
        return retroArchStore.core(withIdentifier: identifier)
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
