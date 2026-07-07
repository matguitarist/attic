import SwiftUI
import SwiftData
import RomsBoxPersistence
import RomsBoxEmulation

struct RetroArchSettingsView: View {
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
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
                Section("Default Core Per System") {
                    ForEach(systems) { system in
                        Picker(system.displayName, selection: coreBinding(for: system)) {
                            Text("None").tag(Optional<String>.none)
                            ForEach(retroArchStore.cores(for: system.systemID)) { core in
                                Text(core.displayName).tag(Optional(core.coreIdentifier))
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

    private func coreBinding(for system: GameSystem) -> Binding<String?> {
        Binding(
            get: {
                if case .retroArchCore(let identifier) = system.defaultLaunchTarget {
                    return identifier
                }
                return nil
            },
            set: { newValue in
                system.defaultLaunchTarget = newValue.map { .retroArchCore(coreIdentifier: $0) }
                try? system.modelContext?.save()
            }
        )
    }
}
