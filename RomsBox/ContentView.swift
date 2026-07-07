import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence

/// Placeholder root view with a Phase 5 scan-orchestration smoke test.
/// Replaced by the NavigationSplitView library browser (Phase 6) and a
/// proper Settings scene for ROMs-root management (also Phase 6).
struct ContentView: View {
    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Query(sort: \GameSystem.displayName) private var systems: [GameSystem]
    @Query(sort: \Game.title) private var games: [Game]
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("RomsBox")
                    .font(.title)
            }

            HStack {
                Button("Add ROMs Folder…") { isChoosingFolder = true }
                Button("Rescan Library") {
                    Task { await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs) }
                }
                .disabled(romsRootsStore.rootURLs.isEmpty || scanCoordinator.state == .scanning)
            }

            if romsRootsStore.rootURLs.isEmpty {
                Text("No ROMs folders configured yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(romsRootsStore.rootURLs, id: \.self) { url in
                    HStack {
                        Text(url.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) { romsRootsStore.removeRoot(url) } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            statusView

            Divider()

            Text("\(systems.count) system(s), \(games.count) game(s) in library")
                .font(.headline)
            List {
                ForEach(systems) { system in
                    Section(system.displayName) {
                        ForEach(games.filter { $0.systemCanonicalID == system.canonicalID }) { game in
                            Text(game.title)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 520, height: 480)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                romsRootsStore.addRoot(url)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch scanCoordinator.state {
        case .idle:
            if let summary = scanCoordinator.lastScanSummary {
                Text(summary).foregroundStyle(.secondary)
            }
        case .scanning:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

#Preview {
    let container = try! RomsBoxModelContainer.makeInMemory()
    ContentView()
        .modelContainer(container)
        .environment(ScanCoordinator(libraryStore: LibraryStore(modelContainer: container)))
        .environment(RomsRootsStore(userDefaults: UserDefaults(suiteName: "preview")!))
}
