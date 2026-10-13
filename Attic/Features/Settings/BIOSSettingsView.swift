import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

/// Every system with games and what its emulator needs from the BIOS
/// folder, missing files first — one place to check instead of each
/// system's panel. Attic only checks: BIOS files are dumped from hardware
/// you own.
struct BIOSSettingsView: View {
    @Query private var systems: [GameSystem]
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    /// Bumped when Attic comes back to the front, so files added in the
    /// Finder show up.
    @State private var check = 0

    private struct Row: Identifiable {
        let system: GameSystem
        let requirements: [BIOSRequirement]
        let files: [BIOSFileStatus]
        var id: String { system.canonicalID }
        var missesRequired: Bool { files.contains { $0.required && !$0.isPresent } }
        var missesOptional: Bool { files.contains { !$0.required && !$0.isPresent } }
    }

    private var rows: [Row] {
        let _ = check
        let bios = emulationFolderStore.folder.bios
        return systems.filter { $0.gameCount > 0 }.sorted(by: GameSystem.displayOrder).map { system in
            let requirements = EmulatorSetupCoordinator.biosRequirements(for: system)
            return Row(system: system, requirements: requirements, files: requirements.statuses(in: bios))
        }
    }

    var body: some View {
        let rows = self.rows
        let missing = rows.filter(\.missesRequired)
        let none = rows.filter(\.files.isEmpty)
        Form {
            Section {
                Label {
                    Text(missing.isEmpty
                         ? String(localized: "Every system you have games for has the BIOS files it needs.")
                         : String(localized: "\(missing.count) systems are missing a BIOS file they need, so their games won't start."))
                } icon: {
                    Image(systemName: missing.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(missing.isEmpty ? .green : .orange)
                }
                Button("Show BIOS Folder") { NSWorkspace.shared.open(emulationFolderStore.folder.bios) }
            } footer: {
                Text("Dump BIOS files from hardware you own; Attic never downloads them. What's needed follows each system's chosen emulator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // In the library's order (by maker, then release), each with
            // its status, so a maker's consoles stay together.
            ForEach(rows.filter { !$0.files.isEmpty }) { row in
                section(row)
            }
            if !none.isEmpty {
                Section {
                    Text(none.map(\.system.displayName).formatted(.list(type: .and)))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("No BIOS Needed")
                }
            }
        }
        .formStyle(.grouped)
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                emulationFolderStore.folder.movePS2BIOSIntoPlace()
                check += 1
            }
        }
        .onAppear {
            emulationFolderStore.folder.movePS2BIOSIntoPlace()
            check += 1
        }
    }

    private func section(_ row: Row) -> some View {
        Section {
            ForEach(row.files) { BIOSFileRow(file: $0) }
            if row.missesRequired || row.missesOptional {
                Button("Show BIOS Folder") {
                    BIOSFileRow.showFolder(for: row.requirements, bios: emulationFolderStore.folder.bios)
                }
            }
        } header: {
            HStack {
                Text(row.system.displayName)
                Spacer()
                if row.missesRequired {
                    Text("Missing").foregroundStyle(.orange)
                } else if row.missesOptional {
                    Text("Ready, some optional files missing").foregroundStyle(.secondary)
                } else {
                    Text("Ready").foregroundStyle(.green)
                }
            }
        }
    }
}
