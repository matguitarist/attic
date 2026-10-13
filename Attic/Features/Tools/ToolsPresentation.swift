import SwiftUI
import AtticLibraryScanning

/// Shows the Tools menu's reports and results in the window they were
/// asked for from.
struct ToolsReports: ViewModifier {
    let host: ToolsCoordinator.Host
    @Environment(ToolsCoordinator.self) private var tools
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(EmulationFolderStore.self) private var emulationFolderStore

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { tools.reportHost == host ? tools.report : nil }, set: { tools.report = $0 })) { report in
                let roots = romsRootsStore.rootURLs
                let root = roots.first?.deletingLastPathComponent() ?? URL(fileURLWithPath: "/")
                switch report {
                case .tidy(let plan):
                    TidyReportView(plan: plan, root: root) { approved in
                        Task { await tools.tidy(approved, romsRoots: roots, scanCoordinator: scanCoordinator) }
                    }
                case .compress(let plan):
                    CompressReportView(plan: plan, root: root) { approved in
                        Task { await tools.compress(approved, romsRoots: roots, scanCoordinator: scanCoordinator) }
                    }
                case .verify(let report):
                    let dats = emulationFolderStore.folder.dats
                    VerifyReportView(report: report, datsFolder: dats) {
                        Task { await tools.verify(datsFolder: dats, scanCoordinator: scanCoordinator, from: host) }
                    } onRename: { games in
                        Task {
                            await tools.rename(games, emulationFolder: emulationFolderStore.folder,
                                               romsRoots: roots, scanCoordinator: scanCoordinator)
                        }
                    }
                }
            }
            .alert(
                tools.outcome?.title ?? "",
                isPresented: Binding(get: { tools.reportHost == host && tools.outcome != nil }, set: { if !$0 { tools.outcome = nil } })
            ) {
                Button("OK") { tools.outcome = nil }
            } message: {
                Text(tools.outcome?.message ?? "")
            }
    }
}

extension View {
    func toolsReports(in host: ToolsCoordinator.Host) -> some View {
        modifier(ToolsReports(host: host))
    }
}

/// While a tool runs: what it's doing, and how far along.
struct ToolsStatusBar: View {
    @Environment(ToolsCoordinator.self) private var tools

    var body: some View {
        if let activity = tools.activity {
            HStack(spacing: 10) {
                if let fraction = activity.fraction {
                    ProgressView(value: fraction)
                        .frame(maxWidth: 240)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(activity.detail.isEmpty ? activity.title : "\(activity.title) \(activity.detail)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } else if tools.isAnalyzing {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Looking through the ROMs folders…")
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
