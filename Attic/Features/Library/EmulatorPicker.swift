import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// A picker's choices of what can run `systemID`'s games: its installed
/// RetroArch cores, then the standalone emulators set up for it. Each is
/// tagged with its `LaunchTargetReference?`.
struct LaunchTargetChoices: View {
    let systemID: CanonicalSystemID

    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]

    var body: some View {
        let cores = retroArchStore.cores(for: systemID)
        if !cores.isEmpty {
            Section("RetroArch Cores") {
                ForEach(cores) { core in
                    Text(core.displayName)
                        .tag(Optional(LaunchTargetReference.retroArchCore(coreIdentifier: core.coreIdentifier)))
                }
            }
        }
        let matching = profiles.filter { $0.assignedSystemIDs.contains(systemID) || $0.assignedSystemIDs.contains(systemID.baseSystem) }
        if !matching.isEmpty {
            Section("Standalone Emulators") {
                ForEach(matching) { profile in
                    Text(profile.name)
                        .tag(Optional(LaunchTargetReference.emulatorProfile(id: profile.id)))
                }
            }
        }
    }
}

/// The game's emulator in its info: its system's, or one picked for this
/// game alone when it runs better there.
struct GameEmulatorRow: View {
    let game: Game

    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]

    var body: some View {
        if let system = game.system {
            // Read here, not in the binding, so the row redraws when it changes.
            let override = game.launchOverride
            Picker("Emulator", selection: Binding(
                get: { override },
                set: { newValue in
                    game.launchOverride = newValue
                    try? game.modelContext?.save()
                }
            )) {
                Text(systemDefaultTitle(system)).tag(LaunchTargetReference?.none)
                Divider()
                LaunchTargetChoices(systemID: system.systemID)
            }
            .help("Pick another emulator for this game only; the system's other games keep theirs")
        }
    }

    private func systemDefaultTitle(_ system: GameSystem) -> String {
        guard let target = system.defaultLaunchTarget else { return String(localized: "System Default (None)") }
        return String(localized: "System Default (\(name(of: target)))")
    }

    private func name(of target: LaunchTargetReference) -> String {
        switch target {
        case .retroArchCore(let identifier):
            retroArchStore.core(withIdentifier: identifier)?.displayName ?? identifier
        case .emulatorProfile(let id):
            profiles.first { $0.id == id }?.name ?? String(localized: "Missing Emulator")
        }
    }
}
