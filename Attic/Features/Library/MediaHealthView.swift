import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticLibraryScanning

/// What's missing or wrong in the library: its media, and info that's
/// likely another game's.
struct LibraryHealthView: View {
    static let windowID = "library-health"

    enum Tab: String {
        case media, info
    }

    @AppStorage("libraryHealthTab") private var tab = Tab.media

    var body: some View {
        Group {
            switch tab {
            case .media: MediaHealthView()
            case .info: GameInfoHealthView()
            }
        }
        .navigationTitle("Library Health")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $tab) {
                    Text("Media").tag(Tab.media)
                    Text("Game Info").tag(Tab.info)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

/// How complete and sound each system's media is: how many games have
/// each kind, and the files that are there but wrong, with a way to deal
/// with each.
struct MediaHealthView: View {

    @Environment(ScanCoordinator.self) private var scanCoordinator
    @Environment(RomsRootsStore.self) private var romsRootsStore
    @Environment(\.modelContext) private var modelContext
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore
    @State private var reports: [MediaHealth.Report]?
    /// Looking for better files: how far along, and what it found.
    @State private var search: Search?
    @State private var searchTask: Task<Void, Never>?
    /// Files nothing better was found for, so their button says so.
    @State private var nothingBetter: Set<MediaHealth.Finding.ID> = []

    struct Search: Equatable {
        var done = 0
        let total: Int
        var replaced = 0
        var current: MediaHealth.Finding.ID?
    }
    @State private var selection: MediaHealth.Report.ID?
    /// Bumped to check again.
    @State private var checks = 0

    /// What the last check found in each file.
    private static var cacheURL: URL {
        URL.cachesDirectory.appending(path: "Attic/Media Health.json")
    }

    /// Every kind's column, in the order of the media folders.
    private static let kinds: [MediaKind] = [.covers, .boxes3D, .physicalMedia, .logos, .fanart, .screenshots, .videos,
                                             .manuals, .marquees, .bezels]

    var body: some View {
        VStack(spacing: 0) {
            if let reports {
                VSplitView {
                    // Both fill the window, whatever the chosen system's
                    // problems would size them to.
                    table(reports)
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
                    problems(reports.first { $0.id == selection })
                        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView("Checking your media…")
                    if !FileManager.default.fileExists(atPath: Self.cacheURL.path) {
                        Text("The first check opens every picture and takes a minute or so; later ones only look at what changed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    checks += 1
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .disabled(reports == nil)
                .help("Check every system's media again")
            }
        }
        .task(id: checks) {
            reports = nil
            let games = await scanCoordinator.gameMedia().map {
                MediaHealth.Game(title: $0.title, system: $0.system, systemFolder: $0.systemFolder,
                                 romRelativePath: $0.relativePath, coverPath: $0.coverPath, path: $0.path)
            }
            let cacheURL = Self.cacheURL
            let checked = await Task.detached(priority: .userInitiated) {
                let result = MediaHealth.check(games, cache: .load(from: cacheURL))
                result.cache.save(to: cacheURL)
                return result.reports
            }.value
            reports = checked
            if selection == nil || !checked.contains(where: { $0.id == selection }) {
                selection = checked.first { !$0.findings.isEmpty }?.id ?? checked.first?.id
            }
        }
    }

    // MARK: - Systems

    private func table(_ reports: [MediaHealth.Report]) -> some View {
        Table(reports, selection: $selection) {
            TableColumn("System") { report in
                HStack(spacing: 6) {
                    Text(name(of: report))
                    if !report.findings.isEmpty {
                        Text(verbatim: "\(report.findings.count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 6)
                            .background(.orange.opacity(0.25), in: Capsule())
                            .help(String(localized: "\(report.findings.count) files to look at"))
                    }
                }
            }
            .width(min: 160, ideal: 210)
            TableColumn("Games") { report in
                Text(report.games.formatted()).monospacedDigit()
            }
            .width(55)
            TableColumnForEach(Self.kinds, id: \.self) { kind in
                TableColumn(Text("\(Image(systemName: Self.symbol(kind))) \(kind.title)")) { report in
                    coverage(kind, in: report)
                }
                .width(min: 70, ideal: 96)
            }
        }
    }

    /// A check when every game has it, else how many do, as a share that
    /// always fits; the counts are in its help. Dimmed when it doesn't apply.
    @ViewBuilder
    private func coverage(_ kind: MediaKind, in report: MediaHealth.Report) -> some View {
        if report.kinds.contains(kind) {
            let have = report.have[kind] ?? 0
            let share = report.games == 0 ? 1 : Double(have) / Double(report.games)
            HStack(spacing: 4) {
                if have == report.games {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if have == 0 {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    Text(verbatim: "0%").foregroundStyle(.secondary)
                } else {
                    Image(systemName: share >= 0.9 ? "circle.inset.filled" : "circle.lefthalf.filled")
                        .foregroundStyle(share >= 0.9 ? .yellow : .orange)
                    // Never 0% or 100% when some, but not all, have it.
                    Text(max(0.01, min(share, 0.99)).formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .monospacedDigit()
            .help(String(localized: "\(have) of \(report.games) games"))
        } else {
            Text(verbatim: "—").foregroundStyle(.tertiary)
                .help(String(localized: "Not a kind of media this system has"))
        }
    }

    private static func symbol(_ kind: MediaKind) -> String { GameMediaSection.symbol(kind) }

    private func name(of report: MediaHealth.Report) -> String {
        SystemTaxonomy.definition(for: report.system)?.displayName ?? report.folder.lastPathComponent
    }

    // MARK: - Problems

    @ViewBuilder
    private func problems(_ report: MediaHealth.Report?) -> some View {
        if let report, !report.findings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(name(of: report)): \(report.findings.count) files to look at")
                        .font(.headline)
                    Spacer()
                    let broken = report.findings.filter { $0.problem == .blank || $0.problem == .unreadable }
                    if !broken.isEmpty {
                        Button("Move \(broken.count) Broken Files to the Trash") { trash(broken.map(\.file)) }
                            .help("Blank and unreadable files, so the game can get a good one")
                    }
                    let improvable = report.findings.filter(canFindBetter)
                    if let search {
                        ProgressView(value: Double(search.done), total: Double(search.total))
                            .frame(width: 80)
                        Text("Looking: \(search.done) of \(search.total), \(search.replaced) replaced")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Stop") { searchTask?.cancel() }
                    } else if improvable.count > 1 {
                        Button("Find Better for \(improvable.count)") { findBetter(improvable) }
                            .disabled(sources.isEmpty || scrapeCoordinator.isBatchRunning)
                            .help(sources.isEmpty ? String(localized: "Set up ScreenScraper or TheGamesDB in Settings first")
                                                  : String(localized: "Looks on ScreenScraper, then TheGamesDB, keeping each file unless a sharper one is found"))
                    }
                    if report.findings.contains(where: { $0.problem == .coverNotBox }) {
                        Button("Rescan \(name(of: report))") {
                            Task {
                                await scanCoordinator.scan(romsRootURLs: romsRootsStore.rootURLs, only: [report.system])
                                checks += 1
                            }
                        }
                        .disabled(scanCoordinator.state == .scanning)
                        .help("Makes each game's 2D box its cover")
                    }
                }
                .padding(12)
                Divider()
                List(report.findings) { finding in
                    row(finding, system: report.system)
                }
                .listStyle(.inset)
            }
        } else {
            ContentUnavailableView {
                Label(report == nil ? "Choose a System" : "Nothing to Fix", systemImage: report == nil ? "list.bullet" : "checkmark.seal")
            } description: {
                if report != nil {
                    Text("No blank, unreadable or small files, and every 2D box is its game's cover. The table shows what each game is missing.")
                }
            }
        }
    }

    private func row(_ finding: MediaHealth.Finding, system: CanonicalSystemID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(finding.problem))
                .foregroundStyle(finding.problem == .coverNotBox ? .blue : .orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                Text("\(finding.kind.title(for: system)) · \(description(finding.problem))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canFindBetter(finding) {
                if search?.current == finding.id {
                    ProgressView().controlSize(.small)
                } else if nothingBetter.contains(finding.id) {
                    Text("Nothing Better Found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Find a Better One") { findBetter([finding]) }
                        .buttonStyle(.link)
                        .disabled(search != nil || sources.isEmpty || scrapeCoordinator.isBatchRunning)
                        .help(sources.isEmpty ? String(localized: "Set up ScreenScraper or TheGamesDB in Settings first")
                                              : String(localized: "Looks on ScreenScraper, then TheGamesDB, keeping this file unless a sharper one is found"))
                }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.file]) }
                .buttonStyle(.link)
            if finding.problem == .blank || finding.problem == .unreadable {
                Button("Move to Trash") { trash([finding.file]) }
                    .buttonStyle(.link)
            }
        }
        .padding(.vertical, 2)
    }

    private func symbol(_ problem: MediaHealth.Problem) -> String {
        switch problem {
        case .blank: "eye.slash"
        case .unreadable: "exclamationmark.triangle"
        case .small: "arrow.down.right.and.arrow.up.left"
        case .coverNotBox: "photo.badge.arrow.down"
        }
    }

    private func description(_ problem: MediaHealth.Problem) -> String {
        switch problem {
        case .blank: String(localized: "Blank: nothing shows")
        case .unreadable: String(localized: "Can't be opened")
        case .small(let width, let height): String(localized: "Small: \(width) × \(height)")
        case .coverNotBox: String(localized: "Its 2D box isn't its cover yet: rescan the system")
        }
    }

    // MARK: - Finding better

    /// A file that's small, blank or broken, of a kind a scraper brings.
    private func canFindBetter(_ finding: MediaHealth.Finding) -> Bool {
        finding.problem != .coverNotBox && finding.gamePath != nil && ScrapeCoordinator.scrapedKinds.contains(finding.kind)
    }

    /// ScreenScraper first, as it matches by file; then TheGamesDB.
    private var sources: [ScrapeCoordinator.ScraperSource] {
        var sources: [ScrapeCoordinator.ScraperSource] = []
        if screenScraperCredentialsStore.isConfigured { sources.append(.screenScraper(screenScraperCredentialsStore.credentials)) }
        if theGamesDBCredentialsStore.isConfigured { sources.append(.theGamesDB(theGamesDBCredentialsStore.credentials)) }
        sources.append(.launchBox)
        return sources
    }

    /// One at a time with a pause, as a batch scrape does: free accounts
    /// allow few requests at once.
    private func findBetter(_ findings: [MediaHealth.Finding]) {
        let sources = sources
        search = Search(total: findings.count)
        searchTask = Task {
            for finding in findings {
                if Task.isCancelled { break }
                search?.current = finding.id
                let path = finding.gamePath ?? ""
                if let game = try? modelContext.fetch(FetchDescriptor<Game>(predicate: #Predicate { $0.romAbsolutePath == path })).first,
                   await scrapeCoordinator.findBetter(finding.kind, than: finding.file, for: game, sources: sources) {
                    search?.replaced += 1
                } else {
                    nothingBetter.insert(finding.id)
                }
                search?.done += 1
                try? await Task.sleep(for: .milliseconds(300))
            }
            search = nil
            searchTask = nil
            checks += 1
        }
    }

    private func trash(_ files: [URL]) {
        for file in files { try? FileManager.default.trashItem(at: file, resultingItemURL: nil) }
        checks += 1
    }
}
