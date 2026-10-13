import SwiftUI
import UniformTypeIdentifiers

/// What checking the games against No-Intro's DATs found, system by
/// system; or, before there are any DATs, where to get them.
struct VerifyReportView: View {
    let report: ToolsCoordinator.VerifyReport
    let datsFolder: URL
    /// Runs the check again, after DATs were added.
    let onVerifyAgain: () -> Void
    @Environment(\.dismiss) private var dismiss

    static let datomatic = URL(string: "https://datomatic.no-intro.org/index.php?page=download")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Verify Games")
                    .font(.title2.bold())
                Text(report.datCount == 0
                     ? String(localized: "Attic checks your games against No-Intro's lists of known good dumps, the DAT files. Nothing is changed.")
                     : String(localized: "Each game's data, checked against \(report.datCount) No-Intro DAT files. Nothing has been changed."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            if report.datCount == 0 {
                noDATs
            } else {
                results
            }

            HStack {
                Button("Add DAT Files…") { addDATs() }
                Button("Show DATs Folder") { NSWorkspace.shared.activateFileViewerSelecting([datsFolder]) }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 680, height: 600)
    }

    private var noDATs: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No DAT files yet")
                        .font(.headline)
                    Text("Download them from No-Intro's DAT-o-MATIC: the daily pack has every system, or pick one system's Standard DAT. Then add the files, or the pack's zip as it is.")
                    Link("Open DAT-o-MATIC", destination: Self.datomatic)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Attic doesn't download DATs itself: No-Intro hands them out through its site only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var results: some View {
        Form {
            ForEach(report.systems) { system in
                Section {
                    gameList(String(localized: "Differ from No-Intro's (\(system.differs.count))"), system.differs,
                             help: String(localized: "Named like a game No-Intro lists, but the data isn't that game's: a bad dump, a hack, or another revision."))
                    gameList(String(localized: "Not in No-Intro's list (\(system.unknown.count))"), system.unknown,
                             help: String(localized: "Homebrew, hacks, translations, prototypes, or dumps No-Intro doesn't list."))
                    gameList(String(localized: "Verified under another name (\(system.renamed.count))"), system.renamed,
                             help: String(localized: "Good dumps, with file names of their own."))
                } header: {
                    HStack {
                        Text(system.name)
                        Spacer()
                        let checked = system.verified + system.differs.count + system.unknown.count
                        Label(String(localized: "\(system.verified) of \(checked) verified"),
                              systemImage: system.verified == checked ? "checkmark.seal.fill" : "checkmark.seal")
                            .foregroundStyle(system.verified == checked ? .green : .secondary)
                    }
                }
            }

            if !report.withoutDAT.isEmpty {
                Section {
                    ForEach(report.withoutDAT, id: \.name) { system in
                        LabeledContent(system.name, value: String(localized: "\(system.games) games"))
                    }
                } header: {
                    Text("No DAT")
                } footer: {
                    Text("Add these systems' DATs to check their games too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !report.unmatchedDATs.isEmpty {
                Section {
                    ForEach(report.unmatchedDATs, id: \.self) { Text(verbatim: $0) }
                } header: {
                    Text("DATs for systems Attic doesn't have")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func gameList(_ title: String, _ games: [ToolsCoordinator.VerifyReport.Game], help: String) -> some View {
        if !games.isEmpty {
            DisclosureGroup {
                ForEach(games.prefix(300), id: \.self) { game in
                    HStack {
                        Text(verbatim: URL(fileURLWithPath: game.path).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if let name = game.datName {
                            Text(verbatim: name)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.callout)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: game.path)]) }
                    }
                }
                if games.count > 300 {
                    Text("and \(games.count - 300) more").foregroundStyle(.secondary)
                }
            } label: {
                Text(title)
                Text(help)
            }
        }
    }

    /// Copies the chosen DATs (or zips of them) into the DATs folder, then
    /// checks again.
    private func addDATs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "dat") ?? .data, .xml, .zip]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        try? FileManager.default.createDirectory(at: datsFolder, withIntermediateDirectories: true)
        for url in panel.urls {
            let target = datsFolder.appending(path: url.lastPathComponent)
            guard url.standardizedFileURL != target.standardizedFileURL else { continue }
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: url, to: target)
        }
        dismiss()
        onVerifyAgain()
    }
}
