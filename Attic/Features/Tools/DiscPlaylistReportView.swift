import SwiftUI
import AtticLibraryScanning

/// The playlists Disc Playlists would write or fix, and those naming discs
/// that aren't there, to look through before anything is written.
struct DiscPlaylistReportView: View {
    let plan: DiscPlaylistPlan
    /// The Emulation folder, so paths read short.
    let root: URL
    let onApply: (DiscPlaylistPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var creating = true
    @State private var fixing = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disc Playlists")
                    .font(.title2.bold())
                Text("Nothing has changed yet. A playlist (.m3u) lists a game's discs, so the game shows once and the emulator can swap discs when it asks. Discs stay where they are.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                if !plan.missing.isEmpty {
                    Section {
                        DisclosureGroup {
                            rows(plan.missing.map { playlist in
                                Row(text: short(playlist.url), detail: String(localized: "\(playlist.discs.count) discs"),
                                    url: playlist.discs[0])
                            })
                        } label: {
                            Toggle(isOn: $creating) {
                                Text("Create playlists")
                                Text("\(plan.missing.count) multi-disc games have none. Each gets one named after the game, listing its discs in order.")
                            }
                        }
                    }
                }
                if !plan.windows.isEmpty {
                    Section {
                        DisclosureGroup {
                            rows(plan.windows.map { Row(text: short($0), url: $0) })
                        } label: {
                            Toggle(isOn: $fixing) {
                                Text("Fix playlists made on Windows")
                                Text("\(plan.windows.count) playlists name their discs the Windows way (\\MultiDisc\\Game.chd), which emulators here can't follow. Their paths are rewritten.")
                            }
                        }
                    }
                }
                if !plan.broken.isEmpty {
                    Section {
                        DisclosureGroup {
                            rows(plan.broken.map { broken in
                                Row(text: short(broken.playlist), detail: broken.absent.joined(separator: ", "), url: broken.playlist)
                            })
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Playlists with missing discs")
                                Text("\(plan.broken.count) playlists name discs that aren't there. Attic leaves them be: add the discs, or remove the playlist.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(plan.missing.isEmpty && plan.windows.isEmpty ? "Done" : "Write Playlists") {
                    let approved = plan.only(creating: creating, fixing: fixing)
                    if !approved.isEmpty { onApply(approved) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 640, height: 520)
    }

    private struct Row {
        let text: String
        var detail: String?
        let url: URL
    }

    @ViewBuilder
    private func rows(_ rows: [Row]) -> some View {
        ForEach(Array(rows.prefix(300).enumerated()), id: \.offset) { _, row in
            HStack {
                Text(verbatim: row.text)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                if let detail = row.detail {
                    Text(verbatim: detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([row.url]) }
            }
        }
        if rows.count > 300 {
            Text("and \(rows.count - 300) more")
                .foregroundStyle(.secondary)
        }
    }

    private func short(_ url: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }
}
