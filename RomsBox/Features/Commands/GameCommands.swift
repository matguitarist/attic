import SwiftUI
import RomsBoxPersistence

extension FocusedValues {
    /// The library window's currently selected game, published with
    /// `.focusedSceneValue` so menu bar commands act on it.
    @Entry var selectedGame: Game?
}

/// The menu bar's Game menu. Gives every per-game action a standard
/// keyboard shortcut and a discoverable home, the way native Mac apps do,
/// instead of living only in context menus and inspector buttons.
struct GameCommands: Commands {
    let launchCoordinator: LaunchCoordinator
    let retroArchStore: RetroArchSettingsStore

    @FocusedValue(\.selectedGame) private var game

    var body: some Commands {
        CommandMenu("Game") {
            Button("Play") {
                if let game { launchCoordinator.play(game: game, retroArchStore: retroArchStore) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(game == nil)

            Button(game?.favorite == true ? "Remove from Favorites" : "Add to Favorites") {
                guard let game else { return }
                game.favorite.toggle()
                try? game.modelContext?.save()
            }
            .keyboardShortcut("d")
            .disabled(game == nil)

            Divider()

            Button("Reveal in Finder") {
                if let game { NSWorkspace.shared.activateFileViewerSelecting([game.romAbsoluteURL]) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(game == nil)
        }
    }
}
