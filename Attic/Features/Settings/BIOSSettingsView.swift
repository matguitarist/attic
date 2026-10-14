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
    @AppStorage("biosShowsAllSystems") private var showsAllSystems = false

    private struct Row: Identifiable {
        let system: GameSystem
        let requirements: [BIOSRequirement]
        let files: [BIOSFileStatus]
        var id: String { system.canonicalID }
        var missesRequired: Bool { files.contains { $0.required && !$0.isPresent } }
        var missesOptional: Bool { files.contains { !$0.required && !$0.isPresent } }
        var hasUnknownDump: Bool { files.contains { $0.isPresent && $0.verdict == .unrecognized } }
    }

    private var rows: [Row] {
        let _ = check
        let bios = emulationFolderStore.folder.bios
        // Hack folders run on their base system's BIOS, already listed.
        let shown = showsAllSystems ? systems.filter { !$0.systemID.isROMHacks } : systems.filter { $0.gameCount > 0 }
        return shown.sorted(by: GameSystem.displayOrder).map { system in
            let requirements = EmulatorSetupCoordinator.biosRequirements(for: system)
            return Row(system: system, requirements: requirements, files: requirements.statuses(in: bios))
        }
    }

    var body: some View {
        let rows = self.rows
        let missing = rows.filter(\.missesRequired)
        // Everything worth a look: missing files and dumps that aren't
        // known ones, so none of them hides further down.
        let problems = rows.filter { $0.missesRequired || $0.hasUnknownDump }
        let none = rows.filter(\.files.isEmpty)
        ScrollViewReader { proxy in
        Form {
            Section {
                Label {
                    Text(problems.isEmpty
                         ? String(localized: "Every system you have games for has the BIOS files it needs.")
                         : missing.isEmpty
                         ? String(localized: "Every system has its BIOS files, but some aren't known good dumps.")
                         : String(localized: "\(missing.count) systems are missing a BIOS file they need, so their games won't start."))
                } icon: {
                    Image(systemName: problems.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(problems.isEmpty ? .green : .orange)
                }
                ForEach(problems) { row in
                    LabeledContent {
                        HStack {
                            tags(row)
                            Button("Show") { withAnimation { proxy.scrollTo(row.id, anchor: .top) } }
                                .buttonStyle(.link)
                        }
                    } label: {
                        Text(row.system.displayName)
                    }
                }
                HStack {
                    Button("Show BIOS Folder") { NSWorkspace.shared.open(emulationFolderStore.folder.bios) }
                    Spacer()
                    Toggle("Show systems without games", isOn: $showsAllSystems)
                }
            } footer: {
                Text("Dump BIOS files from hardware you own; Attic never downloads them. What's needed follows each system's chosen emulator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // In the library's order (by maker, then release), each with
            // its status, so a maker's consoles stay together.
            ForEach(rows.filter { !$0.files.isEmpty }) { row in
                section(row).id(row.id)
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
        }
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
            ForEach(row.files) { BIOSFileRow(file: $0) { check += 1 } }
            if row.missesRequired || row.missesOptional {
                Button("Show BIOS Folder") {
                    BIOSFileRow.showFolder(for: row.requirements, bios: emulationFolderStore.folder.bios)
                }
            }
        } header: {
            HStack {
                Text(row.system.displayName)
                Spacer()
                tags(row)
            }
        }
    }

    /// A system's state as tags, as in its panel.
    private func tags(_ row: Row) -> some View {
        let verified = row.files.count { $0.isPresent && $0.verdict == .verified }
        let found = row.files.count { $0.isPresent && $0.verdict == .unchecked }
        let unknown = row.files.count { $0.isPresent && $0.verdict == .unrecognized }
        let missing = row.files.count { !$0.isPresent && $0.required }
        let optional = row.files.count { !$0.isPresent && !$0.required }
        return HStack(spacing: 4) {
            if missing > 0 { StatusTag(text: String(localized: "\(missing) missing"), systemImage: "exclamationmark.triangle.fill", tint: .orange) }
            if unknown > 0 { StatusTag(text: String(localized: "\(unknown) not known"), systemImage: "exclamationmark.circle", tint: .orange) }
            if verified > 0 { StatusTag(text: String(localized: "\(verified) verified"), systemImage: "checkmark.seal.fill", tint: .green) }
            if found > 0 { StatusTag(text: String(localized: "\(found) found"), systemImage: "checkmark.circle.fill", tint: .green) }
            if optional > 0 { StatusTag(text: String(localized: "\(optional) optional"), tint: .secondary) }
        }
    }
}
