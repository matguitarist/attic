import SwiftUI
import AtticLibraryScanning

/// What Tidy Up would do, part by part, to look through before anything
/// moves: each part can be left out, and lists its files.
struct TidyReportView: View {
    let plan: MediaTidyPlan
    /// The Emulation folder, so paths read short.
    let root: URL
    let onTidy: (MediaTidyPlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<MediaTidyPlan.Step> = []
    @State private var chdman = CHDConversion.findCHDMan()
    @State private var isInstallingCHDMan = false
    @State private var chdmanError: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tidy Up Report")
                    .font(.title2.bold())
                Text("Nothing has changed yet. Untick what you'd rather keep as it is, then tidy up. Everything removed goes to the Trash. Your saves and BIOS files aren't touched, and your games only if you tick Duplicate games.")
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
                                    if let bytes = row.bytes {
                                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
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
                            .disabled(step == .compressDiscs && chdman == nil)
                        }
                        if step == .compressDiscs, chdman == nil {
                            chdmanRow
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !selectedTrash.isEmpty {
                    Text("\(ByteCountFormatter.string(fromByteCount: selectedTrash.trashBytes, countStyle: .file)) to the Trash")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Tidy Up") {
                    onTidy(plan.only(chdman == nil ? selected.subtracting([.compressDiscs]) : selected))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 640, height: 600)
        // Duplicates are games, and CHD rewrites them (and takes a while):
        // only when asked for.
        .onAppear { selected = Set(plan.steps).subtracting([.trash(.duplicates), .compressDiscs]) }
    }

    private var selectedTrash: MediaTidyPlan { plan.only(selected) }

    /// Homebrew, which can install `chdman` (its rom-tools package is built
    /// from MAME's own source).
    private static var brew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private var chdmanRow: some View {
        HStack {
            if let chdmanError {
                Text(chdmanError).foregroundStyle(.orange)
            } else if Self.brew != nil {
                Text("Needs MAME's chdman tool, which Homebrew can install.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Needs MAME's chdman tool: install Homebrew (brew.sh), then run “brew install rom-tools” in Terminal.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isInstallingCHDMan {
                ProgressView().controlSize(.small)
            } else if let brew = Self.brew {
                Button("Install chdman") {
                    isInstallingCHDMan = true
                    chdmanError = nil
                    Task {
                        let ok = await Task.detached { () -> Bool in
                            let process = Process()
                            process.executableURL = brew
                            process.arguments = ["install", "rom-tools"]
                            process.standardOutput = FileHandle.nullDevice
                            process.standardError = FileHandle.nullDevice
                            guard (try? process.run()) != nil else { return false }
                            process.waitUntilExit()
                            return process.terminationStatus == 0
                        }.value
                        isInstallingCHDMan = false
                        chdman = CHDConversion.findCHDMan()
                        if !ok || chdman == nil { chdmanError = String(localized: "Homebrew couldn't install rom-tools. Try “brew install rom-tools” in Terminal.") }
                    }
                }
            }
        }
        .font(.callout)
    }

    private func binding(for step: MediaTidyPlan.Step) -> Binding<Bool> {
        Binding(
            get: { selected.contains(step) },
            set: { if $0 { selected.insert(step) } else { selected.remove(step) } }
        )
    }

    // MARK: - Text

    private func title(for step: MediaTidyPlan.Step) -> String {
        switch step {
        case .moveMedia: String(localized: "Move media into the Media folder")
        case .gamelists: String(localized: "Fix gamelists")
        case .compressCovers: String(localized: "Save covers as HEIC")
        case .compressManuals: String(localized: "Compress heavy manual scans")
        case .compressDiscs: String(localized: "Compress disc games to CHD")
        case .trash(.unusedFolders): String(localized: "Folders Attic doesn't use")
        case .trash(.noGames): String(localized: "Media and gamelists of systems with no games")
        case .trash(.otherApps): String(localized: "Other apps' files")
        case .trash(.unshownMedia): String(localized: "Media Attic doesn't show")
        case .trash(.missingGames): String(localized: "Media for games that aren't there")
        case .trash(.leftoverMedia): String(localized: "What's left in Batocera's media folders")
        case .trash(.duplicates): String(localized: "Duplicate games")
        }
    }

    private func summary(for step: MediaTidyPlan.Step) -> String {
        let count = rows(for: step).count
        switch step {
        case .moveMedia:
            return String(localized: "\(count) files, renamed ES-DE style (Game-boxart.png becomes covers/Game.png).")
        case .gamelists:
            return String(localized: "\(count) gamelists: Batocera's move to Gamelists, and old media paths and missing games come out.")
        case .compressCovers:
            return String(localized: "\(count) PNG and JPEG covers, kept only when HEIC is smaller.")
        case .compressManuals:
            return String(localized: "\(count) manuals redrawn at 150 dpi, kept only when that saves at least 40%.")
        case .compressDiscs:
            let bytes = plan.discs.reduce(Int64(0)) { total, disc in
                total + disc.files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            }
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return String(localized: "\(count) games, \(size) now: each becomes one .chd, lossless and usually 30–60% smaller, checked before the original files go to the Trash. Takes a few minutes per game.")
        case .trash(let reason):
            let bytes = plan.trashed.filter { $0.reason == reason }.reduce(0) { $0 + $1.bytes }
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            switch reason {
            case .unusedFolders: return String(localized: "\(count) items, \(size): folders for no system Attic knows, and empty gamelist folders.")
            case .noGames: return String(localized: "\(count) items, \(size).")
            case .otherApps: return String(localized: "\(count) items, \(size): systeminfo.txt, spare gamelists, scraper leftovers.")
            case .unshownMedia: return String(localized: "\(count) items, \(size): fan art, marquees, 3D boxes, mix images, title screens…")
            case .missingGames: return String(localized: "\(count) items, \(size).")
            case .leftoverMedia: return String(localized: "\(count) items, \(size): marquees, fan art and the like, once the rest has moved.")
            case .duplicates: return String(localized: "\(count) items, \(size): other regions, revisions and betas of games you have, with their media. The kept copy is a finished release: World, then USA, Europe, Japan, then the latest revision. Your games themselves, so it's off unless you tick it.")
            }
        }
    }

    // MARK: - Rows

    private struct Row {
        let text: String
        let url: URL
        var bytes: Int64?
    }

    private func rows(for step: MediaTidyPlan.Step) -> [Row] {
        switch step {
        case .moveMedia:
            plan.moves.map { Row(text: "\(short($0.from)) → \(short($0.to))", url: $0.from) }
        case .gamelists:
            plan.gamelists.map { Row(text: $0.from == $0.to ? short($0.from) : "\(short($0.from)) → \(short($0.to))", url: $0.from) }
        case .compressCovers:
            plan.compress.map { Row(text: short($0), url: $0) }
        case .compressDiscs:
            plan.discs.map { disc in
                Row(text: short(disc.source) + (disc.files.count > 1 ? String(localized: " (and \(disc.files.count - 1) tracks)") : ""), url: disc.source,
                    bytes: disc.files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) })
            }
        case .compressManuals:
            plan.manuals.map { Row(text: short($0), url: $0, bytes: Int64((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)) }
        case .trash(let reason):
            plan.trashed.filter { $0.reason == reason }.map { trashed in
                let kept = plan.keptCopies[trashed.url].map { String(localized: " (keeps \($0.lastPathComponent))") } ?? ""
                return Row(text: short(trashed.url) + kept, url: trashed.url, bytes: trashed.bytes)
            }
        }
    }

    private func short(_ url: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }
}
