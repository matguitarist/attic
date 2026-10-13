import SwiftUI
import AtticLibraryScanning

/// The games that could take less room, by kind, to look through before
/// anything is rewritten.
struct CompressReportView: View {
    let plan: GameCompressionPlan
    /// The Emulation folder, so paths read short.
    let root: URL
    let onCompress: (GameCompressionPlan) -> Void
    @Environment(ToolsCoordinator.self) private var tools
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<GameCompressionPlan.Step> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compress Games")
                    .font(.title2.bold())
                Text("Nothing has changed yet. Compression is lossless: games play as before, and keep their saves, media and play history. Each new file is checked before the old ones go to the Trash.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                ForEach(plan.steps, id: \.self) { step in
                    Section {
                        DisclosureGroup {
                            ForEach(Array(rows(for: step).prefix(300).enumerated()), id: \.offset) { _, row in
                                HStack {
                                    Text(verbatim: row.text)
                                        .font(.callout.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .contextMenu {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([row.url]) }
                                }
                            }
                            let count = rows(for: step).count
                            if count > 300 {
                                Text("and \(count - 300) more")
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Toggle(isOn: binding(for: step)) {
                                Text(title(for: step))
                                Text(summary(for: step))
                            }
                            .disabled(step == .discs && tools.chdman == nil)
                        }
                        if step == .discs, tools.chdman == nil {
                            CHDManInstallRow()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Compress") {
                    onCompress(plan.only(tools.chdman == nil ? selected.subtracting([.discs]) : selected))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.subtracting(tools.chdman == nil ? [.discs] : []).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 640, height: 560)
        .onAppear { selected = Set(plan.steps) }
    }

    private func binding(for step: GameCompressionPlan.Step) -> Binding<Bool> {
        Binding(
            get: { selected.contains(step) },
            set: { if $0 { selected.insert(step) } else { selected.remove(step) } }
        )
    }

    private func title(for step: GameCompressionPlan.Step) -> String {
        switch step {
        case .discs: String(localized: "Disc games to CHD")
        case .cartridges: String(localized: "Cartridge games to ZIP")
        }
    }

    private func summary(for step: GameCompressionPlan.Step) -> String {
        let rows = rows(for: step)
        let size = ByteCountFormatter.string(fromByteCount: rows.reduce(0) { $0 + $1.bytes }, countStyle: .file)
        switch step {
        case .discs:
            return String(localized: "\(rows.count) games, \(size) now. Each disc becomes one .chd, usually 30–60% smaller; PSP and PS2 discs too. Takes a few minutes per game.")
        case .cartridges:
            return String(localized: "\(rows.count) games, \(size) now. Each becomes a .zip of its own, kept only when it saves at least 10%. Attic unzips a game when it starts.")
        }
    }

    private struct Row {
        let text: String
        let url: URL
        let bytes: Int64
    }

    private func rows(for step: GameCompressionPlan.Step) -> [Row] {
        switch step {
        case .discs:
            plan.discs.map { disc in
                Row(text: short(disc.source) + (disc.files.count > 1 ? String(localized: " (and \(disc.files.count - 1) tracks)") : ""),
                    url: disc.source, bytes: disc.bytes)
            }
        case .cartridges:
            plan.cartridges.map { Row(text: short($0), url: $0, bytes: MediaFolder.fileSize($0)) }
        }
    }

    private func short(_ url: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }
}

/// Says chdman is needed, and installs it through Homebrew when there.
struct CHDManInstallRow: View {
    @Environment(ToolsCoordinator.self) private var tools

    var body: some View {
        HStack {
            if let error = tools.chdmanError {
                Text(error).foregroundStyle(.orange)
            } else if ToolsCoordinator.brew != nil {
                Text("Needs MAME's chdman tool, which Homebrew can install.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Needs MAME's chdman tool: install Homebrew (brew.sh), then run “brew install rom-tools” in Terminal.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if tools.isInstallingCHDMan {
                ProgressView().controlSize(.small)
            } else if ToolsCoordinator.brew != nil {
                Button("Install chdman") { Task { await tools.installCHDMan() } }
            }
        }
        .font(.callout)
    }
}
