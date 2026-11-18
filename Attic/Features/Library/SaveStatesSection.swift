import SwiftUI
import AtticModels
import AtticPersistence
import AtticEmulation

/// The game's RetroArch save states, with the screenshot of each: click one
/// to play from it. Shown only for games RetroArch runs, once they have a
/// numbered state.
struct SaveStatesSection: View {
    let game: Game
    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(RetroArchSettingsStore.self) private var retroArchStore

    var body: some View {
        let states = Self.states(of: game, retroArchStore: retroArchStore)
        if !states.isEmpty {
            Section("Save States") {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(states) { state in
                            Button {
                                launchCoordinator.play(game: game, retroArchStore: retroArchStore, from: state)
                            } label: {
                                SaveStateTile(state: state)
                            }
                            .buttonStyle(.plain)
                            .disabled(launchCoordinator.state == .launching)
                            .help(String(localized: "Play from slot \(state.slot)"))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// Read each time the section draws: a folder listing.
    static func states(of game: Game, retroArchStore: RetroArchSettingsStore) -> [SaveState] {
        guard case .retroArchCore? = LaunchTargetResolution.resolve(
            gameOverride: game.launchOverride, systemDefault: game.system?.defaultLaunchTarget
        ) else { return [] }
        let folder = retroArchStore.emulationFolderStore.folder.states(for: CanonicalSystemID(game.systemCanonicalID))
        return SaveState.list(in: folder, romURL: game.romAbsoluteURL)
    }
}

/// One state: its screenshot, slot and when it was saved.
struct SaveStateTile: View {
    let state: SaveState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let thumbnail = state.thumbnail, let image = NSImage(contentsOf: thumbnail) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            .frame(width: 128, height: 96)
            .clipShape(.rect(cornerRadius: 6))
            Text("Slot \(state.slot)")
                .font(.callout)
            Text(state.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 128, alignment: .leading)
        .contentShape(.rect)
    }
}
