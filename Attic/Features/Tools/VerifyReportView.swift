import SwiftUI
import UniformTypeIdentifiers
import AtticModels
import AtticEmulation

/// What checking the games against No-Intro's DATs found, system by
/// system; or, before there are any DATs, where to get them.
struct VerifyReportView: View {
    let report: ToolsCoordinator.VerifyReport
    let datsFolder: URL
    /// Runs the check again, after DATs were added.
    let onVerifyAgain: () -> Void
    /// Downloads FinalBurn Neo's or MAME's DAT, then checks again.
    let onDownload: (ArcadeVerifier.Source) -> Void
    /// Gives these games No-Intro's names.
    let onRename: ([ToolsCoordinator.VerifyReport.Game]) -> Void
    @Environment(\.dismiss) private var dismiss
    /// The games to rename, by path.
    @State private var toRename: Set<String> = []

    private var renamable: [ToolsCoordinator.VerifyReport.Game] {
        report.systems.flatMap(\.renamed)
    }

    static let datomatic = URL(string: "https://datomatic.no-intro.org/index.php?page=download")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(report.system.map { String(localized: "Verify \(SystemTaxonomy.definition(for: $0)?.displayName ?? $0.rawValue) Games") } ?? String(localized: "Verify Games"))
                    .font(.title2.bold())
                Text(report.datCount == 0
                     ? String(localized: "Attic checks your games against No-Intro's lists of known good dumps, the DAT files. Nothing is changed.")
                     : String(localized: "Each game's data, checked against \(report.datCount) No-Intro DAT files. Nothing has been changed."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            if report.datCount == 0 && report.missingArcadeDATs.isEmpty {
                noDATs
            } else {
                results
            }

            HStack {
                Button("Add DAT Files…") { addDATs() }
                Button("Show DATs Folder") { NSWorkspace.shared.activateFileViewerSelecting([datsFolder]) }
                Spacer()
                if toRename.isEmpty {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(String(localized: "Rename \(toRename.count) Games")) {
                        onRename(renamable.filter { toRename.contains($0.path) })
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 680, height: 600)
        .onAppear { toRename = Set(renamable.filter(\.isPlainRename).map(\.path)) }
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
            if !report.missingArcadeDATs.isEmpty {
                Section {
                    ForEach(report.missingArcadeDATs, id: \.self) { source in
                        LabeledContent {
                            Button("Download") {
                                dismiss()
                                onDownload(source)
                            }
                        } label: {
                            switch source {
                            case .fbneo:
                                Text("FinalBurn Neo's DAT")
                                Text("For Neo Geo, CPS-1, CPS-2, CPS-3 and FinalBurn Neo's other boards. About 14 MB, from FinalBurn Neo's repository.")
                            case .mame:
                                Text("MAME's game list")
                                Text("For MAME, NAOMI, Atomiswave, Model 2 and 3, ST-V and the other boards MAME runs. About 20 MB, from MAME's latest release.")
                            }
                        }
                    }
                } header: {
                    Text("Arcade DATs")
                } footer: {
                    Text("Arcade sets are checked against the version of the emulator that runs them: chip by chip, with what a clone takes from its parent and a game from its BIOS set, and each disc image.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(report.systems) { system in
                let arcade = ToolsCoordinator.isArcade(system.id)
                Section {
                    gameList(String(localized: "Incomplete (\(system.incomplete.count))"), system.incomplete,
                             help: String(localized: "Chips or a disc image are missing: the game may not start."))
                    gameList(arcade ? String(localized: "From another version (\(system.differs.count))") : String(localized: "Differ from No-Intro's (\(system.differs.count))"), system.differs,
                             help: arcade ? String(localized: "Some chips aren't the ones this emulator's version expects: the set comes from another version of MAME or FinalBurn Neo.")
                                          : String(localized: "Named like a game No-Intro lists, but the data isn't that game's: a bad dump, a hack, or another revision."))
                    gameList(arcade ? String(localized: "Not in the DAT (\(system.unknown.count))") : String(localized: "Not in No-Intro's list (\(system.unknown.count))"), system.unknown,
                             help: arcade ? String(localized: "A set this emulator's version doesn't know by that name.")
                                          : String(localized: "Homebrew, hacks, translations, prototypes, or dumps No-Intro doesn't list."))
                    gameList(String(localized: "Verified (\(system.verifiedGames.count))"), system.verifiedGames,
                             help: String(localized: "Known good dumps, as the DAT lists them."))
                } header: {
                    HStack {
                        Text(system.name)
                        Spacer()
                        let checked = system.verified + system.differs.count + system.unknown.count + system.incomplete.count
                        Label(String(localized: "\(system.verified) of \(checked) verified"),
                              systemImage: system.verified == checked ? "checkmark.seal.fill" : "checkmark.seal")
                            .foregroundStyle(system.verified == checked ? .green : .secondary)
                    }
                }
            }

            if !renamable.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(renamable, id: \.path) { game in
                            Toggle(isOn: Binding(
                                get: { toRename.contains(game.path) },
                                set: { if $0 { toRename.insert(game.path) } else { toRename.remove(game.path) } }
                            )) {
                                Text(verbatim: game.stem)
                                Text(verbatim: "→ \(game.datName ?? "")")
                            }
                            .font(.callout)
                        }
                    } label: {
                        Text("Rename to No-Intro's names (\(toRename.count) of \(renamable.count))")
                        Text("Good dumps with file names of their own. Their media, gamelist entries and saves follow, and they keep their play history and collections.")
                    }
                    HStack {
                        Spacer()
                        Button("Select All") { toRename = Set(renamable.map(\.path)) }
                        Button("Select None") { toRename = [] }
                    }
                    .controlSize(.small)
                } header: {
                    Text("File Names")
                } footer: {
                    Text("Names that would add a release tag such as (Proto) or (Virtual Console) aren't ticked: No-Intro sometimes lists the same data under several releases.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                // By name, as the library shows them; the file under it.
                let sorted = games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                ForEach(sorted.prefix(300), id: \.self) { game in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: game.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(verbatim: URL(fileURLWithPath: game.path).lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let detail = game.detail {
                            Text(verbatim: detail)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else if let name = game.datName, name != game.title {
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
