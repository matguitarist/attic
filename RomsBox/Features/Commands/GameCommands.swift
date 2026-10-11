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
    @FocusedValue(\.gameInfoEditor) private var infoEditor
    @FocusedValue(\.collectionCoordinator) private var collectionCoordinator

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Collection…") {
                collectionCoordinator?.newCollection()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(collectionCoordinator == nil)
        }

        CommandMenu("Game") {
            Button("Play") {
                if let game { launchCoordinator.play(game: game, retroArchStore: retroArchStore) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(game == nil)

            Button(game?.favorite == true ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")) {
                guard let game else { return }
                game.favorite.toggle()
                try? game.modelContext?.save()
            }
            .keyboardShortcut("d")
            .disabled(game == nil)

            Button("Edit Info…") {
                infoEditor?.game = game
            }
            .keyboardShortcut("i")

            Button("Add to New Collection…") {
                if let game { collectionCoordinator?.newCollection(with: [game]) }
            }
            .disabled(game == nil || collectionCoordinator == nil)
            .disabled(game == nil || infoEditor == nil)

            Divider()

            Button("Reveal in Finder") {
                if let game { NSWorkspace.shared.activateFileViewerSelecting([game.romAbsoluteURL]) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(game == nil)
        }
    }
}

/// View › Enter Big Box.
struct BigBoxCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Enter Big Box") {
                openWindow(id: BigBoxView.windowID)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }
}

/// Help › RomsBox Help (⌘?) opens the help window instead of the system's
/// "Help isn't available" placeholder.
struct HelpCommands: Commands {
    let navigator: HelpNavigator
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("RomsBox Help") {
                openWindow(id: HelpView.windowID)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

extension HelpNavigator {
    /// Shows `page` in the help window, opening it if needed.
    func open(_ page: HelpPage, with openWindow: OpenWindowAction) {
        selection = page
        openWindow(id: HelpView.windowID)
    }
}
