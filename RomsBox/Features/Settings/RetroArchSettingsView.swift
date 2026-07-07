import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxEmulation

struct RetroArchSettingsView: View {
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]
    @State private var isChoosingApp = false

    var body: some View {
        Form {
            Section("RetroArch") {
                HStack {
                    Text(retroArchStore.installURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: retroArchStore.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(retroArchStore.isInstalled ? .green : .orange)
                }
                Button("Choose RetroArch.app…") { isChoosingApp = true }
            }

            Section("Cores (\(retroArchStore.cores.count) detected)") {
                Button("Refresh Cores") { retroArchStore.refresh() }
                if retroArchStore.cores.isEmpty {
                    Text("No cores detected. Install cores via RetroArch's Online Updater, then Refresh.")
                        .foregroundStyle(.secondary)
                }
            }

            if !systems.isEmpty {
                Section("Default Launch Target Per System") {
                    ForEach(systems) { system in
                        Picker(system.displayName, selection: targetBinding(for: system)) {
                            Text("None").tag(Optional<LaunchTargetReference>.none)

                            let matchingCores = retroArchStore.cores(for: system.systemID)
                            if !matchingCores.isEmpty {
                                Section("RetroArch Cores") {
                                    ForEach(matchingCores) { core in
                                        Text(core.displayName)
                                            .tag(Optional(LaunchTargetReference.retroArchCore(coreIdentifier: core.coreIdentifier)))
                                    }
                                }
                            }

                            let matchingProfiles = profiles.filter { $0.assignedSystemIDs.contains(system.systemID) }
                            if !matchingProfiles.isEmpty {
                                Section("Custom Emulators") {
                                    ForEach(matchingProfiles) { profile in
                                        Text(profile.name)
                                            .tag(Optional(LaunchTargetReference.emulatorProfile(id: profile.id)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result {
                retroArchStore.installURL = url
                retroArchStore.refresh()
            }
        }
    }

    private func targetBinding(for system: GameSystem) -> Binding<LaunchTargetReference?> {
        Binding(
            get: { system.defaultLaunchTarget },
            set: { newValue in
                system.defaultLaunchTarget = newValue
                try? system.modelContext?.save()
            }
        )
    }
}
