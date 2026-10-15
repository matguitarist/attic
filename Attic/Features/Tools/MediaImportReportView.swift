import SwiftUI
import AtticModels

/// What importing from another front-end would bring, before it's done:
/// the systems to take it from, and whether to copy the games the library
/// doesn't have too.
struct MediaImportReportView: View {
    let plan: MediaImportPlan
    /// Where copied games go, for the room left there.
    let romsRoot: URL?
    let onImport: (_ systems: Set<CanonicalSystemID>, _ copyingGames: Bool, _ replacing: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<CanonicalSystemID>
    @State private var copyingGames = false
    @State private var replacing = false

    init(plan: MediaImportPlan, romsRoot: URL?, onImport: @escaping (Set<CanonicalSystemID>, Bool, Bool) -> Void) {
        self.plan = plan
        self.romsRoot = romsRoot
        self.onImport = onImport
        // The systems with your games in them, to start with.
        _chosen = State(initialValue: Set(plan.systems.filter { $0.matched > 0 }.map(\.id)))
    }

    private func counts(of system: MediaImportPlan.System) -> MediaImportPlan.Counts {
        (replacing ? system.available : system.missing) + (copyingGames ? system.newGamesMedia : .init())
    }

    private var chosenSystems: [MediaImportPlan.System] { plan.systems.filter { chosen.contains($0.id) } }

    private var total: MediaImportPlan.Counts {
        chosenSystems.reduce(MediaImportPlan.Counts()) { $0 + counts(of: $1) }
    }

    private var bytesToCopy: Int64 { copyingGames ? chosenSystems.reduce(0) { $0 + $1.newBytes } : 0 }
    private var gamesToCopy: Int { copyingGames ? chosenSystems.reduce(0) { $0 + $1.newGames.count } : 0 }

    private var freeBytes: Int64? {
        guard var url = romsRoot else { return nil }
        // The folder may not be there yet: the room on its disk.
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 { url.deleteLastPathComponent() }
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    private var fits: Bool { freeBytes.map { bytesToCopy < $0 } ?? true }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from Another Front-End")
                    .font(.title2.bold())
                Text(verbatim: plan.folder.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                Section {
                    Toggle(isOn: $copyingGames) {
                        Text("Copy the games you don't have")
                        Text("Into your ROMs folder, with their media and info. The other front-end keeps its own.")
                    }
                    Toggle(isOn: $replacing) {
                        Text("Replace what your games already have")
                        Text("Their media and info are replaced by the other front-end's, where it has some. The files replaced go to the Trash.")
                    }
                }

                Section {
                    ForEach(plan.systems) { system in
                        row(system)
                    }
                } header: {
                    HStack {
                        Text("Systems")
                        Spacer()
                        Button("All") { chosen = Set(plan.systems.map(\.id)) }
                        Button("None") { chosen = [] }
                    }
                    .buttonStyle(.link)
                } footer: {
                    Text("Games are matched by file name. Covers come from each game's thumbnail (the box), screenshots from its image, logos from its marquee (where RetroBat and Batocera keep them); covers, logos and fan art are saved as HEIC when that's smaller.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if gamesToCopy > 0 {
                        Text(String(localized: "\(gamesToCopy) games to copy, \(ByteCountFormatter.string(fromByteCount: bytesToCopy, countStyle: .file))"))
                            .foregroundStyle(fits ? Color.secondary : Color.red)
                        if !fits, let freeBytes {
                            Text(String(localized: "Only \(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)) free on that disk."))
                                .foregroundStyle(.red)
                        }
                    }
                    Text(summary(total))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    dismiss()
                    onImport(chosen, copyingGames, replacing)
                }
                .keyboardShortcut(.defaultAction)
                .disabled((total.isEmpty && gamesToCopy == 0) || !fits)
            }
            .padding(20)
        }
        .frame(width: 660, height: 620)
    }

    private func row(_ system: MediaImportPlan.System) -> some View {
        Toggle(isOn: Binding(
            get: { chosen.contains(system.id) },
            set: { if $0 { chosen.insert(system.id) } else { chosen.remove(system.id) } }
        )) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(system.name)
                    Text(summary(counts(of: system)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if system.matched > 0 {
                        Text(String(localized: "\(system.matched) of your games"))
                            .foregroundStyle(.secondary)
                    }
                    if !system.newGames.isEmpty {
                        Text(String(localized: "\(system.newGames.count) more, \(ByteCountFormatter.string(fromByteCount: system.newBytes, countStyle: .file))"))
                            .font(.caption)
                            .foregroundStyle(copyingGames ? .primary : .tertiary)
                    }
                }
                .monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
    }

    private func summary(_ counts: MediaImportPlan.Counts) -> String {
        guard !counts.isEmpty else { return String(localized: "Nothing to add") }
        var parts: [String] = []
        if counts.covers > 0 { parts.append(String(localized: "\(counts.covers) covers")) }
        if counts.screenshots > 0 { parts.append(String(localized: "\(counts.screenshots) screenshots")) }
        if counts.videos > 0 { parts.append(String(localized: "\(counts.videos) videos")) }
        if counts.manuals > 0 { parts.append(String(localized: "\(counts.manuals) manuals")) }
        if counts.logos > 0 { parts.append(String(localized: "\(counts.logos) logos")) }
        if counts.fanart > 0 { parts.append(String(localized: "\(counts.fanart) fan art images")) }
        if counts.descriptions > 0 { parts.append(String(localized: "\(counts.descriptions) descriptions")) }
        return parts.formatted(.list(type: .and))
    }
}
