import SwiftUI

struct ChooseROMsRootView: View {
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Welcome to Attic")
                .font(.title)

            Text("Choose a ROMs folder to get started. Attic recognizes libraries organized the way Batocera, RetroBat, or ES-DE organize them.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if romsRootsStore.rootURLs.isEmpty {
                Button("Choose ROMs Folder…") { isChoosingFolder = true }
                    .buttonStyle(.borderedProminent)
            } else {
                statusView
                Button("Scan Now") {
                    Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanCoordinator.state == .scanning)
            }
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 360)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            romsRootsStore.addRoot(url)
            Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch scanCoordinator.state {
        case .scanning:
            ProgressView("Scanning…")
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        case .idle:
            if let summary = scanCoordinator.lastScanSummary {
                Text(summary).foregroundStyle(.secondary)
            } else {
                Text("Folder added. Ready to scan.").foregroundStyle(.secondary)
            }
        }
    }
}
