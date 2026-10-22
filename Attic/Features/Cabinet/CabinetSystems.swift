import SwiftUI
import AtticLibraryScanning
import SwiftData
import AtticModels
import AtticPersistence

/// Cabinet Mode's first level: every section (shortcuts, collections,
/// systems) in a strip along the bottom, the focused one's picture, logo,
/// facts and numbers above. Confirm opens its games.
struct CabinetSystemsView: View {
    /// Whether systems and collections play their own video (off by
    /// default: they're long, and loud with sound on).
    static let playsVideosKey = "cabinetPlaysSystemVideos"

    let sections: [CabinetSection]
    @Binding var selection: LibrarySelection
    let onOpen: () -> Void

    @Environment(\.cabinetTheme) private var installed
    @State private var scrolledID: LibrarySelection?

    var body: some View {
        let focused = sections.first { $0.selection == selection } ?? sections.first
        GeometryReader { geometry in
            let stripHeight = min(150, max(90, geometry.size.height * 0.16))
            VStack(spacing: 32) {
                if let focused {
                    CabinetSectionInfo(section: focused)
                        .id(focused.id)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 60)
                }
                strip(height: stripHeight, width: geometry.size.width)
                    .frame(height: stripHeight * 1.3)
            }
            .padding(.top, 36)
            .animation(.easeInOut(duration: 0.25), value: selection)
        }
        .onChange(of: selection, initial: true) { old, new in
            withAnimation(old == new ? nil : .snappy(duration: 0.25)) { scrolledID = new }
        }
        .onChange(of: scrolledID) { _, id in
            if let id, id != selection { selection = id }
        }
    }

    private func strip(height: CGFloat, width: CGFloat) -> some View {
        let tileWidth = height * 2
        return ScrollView(.horizontal) {
            LazyHStack(spacing: installed.theme.tiles.spacing) {
                ForEach(sections) { section in
                    CabinetSectionTile(section: section, isFocused: section.selection == selection)
                        .frame(width: tileWidth, height: height)
                        .id(section.id)
                        .onTapGesture {
                            if section.selection == selection { onOpen() } else { selection = section.selection }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, max(0, (width - tileWidth) / 2), for: .scrollContent)
        .scrollPosition(id: $scrolledID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.never)
    }
}

/// One section in the strip: its logo on a card, else its name.
private struct CabinetSectionTile: View {
    let section: CabinetSection
    let isFocused: Bool

    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let theme = installed.theme
        let shape = RoundedRectangle(cornerRadius: max(theme.tiles.cornerRadius, 10), style: .continuous)
        Group {
            if let logo = section.logo {
                logo
                    .resizable()
                    .scaledToFit()
                    .padding(22)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: section.symbol)
                        .font(theme.largeFont())
                        .foregroundStyle(theme.palette.accent.color)
                    Text(theme.cased(section.title))
                        .font(theme.bodyFont(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.surface.color, in: shape)
        .overlay {
            if isFocused {
                shape.strokeBorder(theme.palette.accent.color, lineWidth: 3)
            }
        }
        .scaleEffect(isFocused ? 1.12 : 0.92)
        .opacity(isFocused ? 1 : theme.tiles.unfocusedOpacity)
        .shadow(color: isFocused && theme.tiles.focusGlow ? theme.palette.accent.color.opacity(0.6) : .clear, radius: 20)
        .animation(.snappy(duration: 0.2), value: isFocused)
        .accessibilityLabel(section.title)
    }
}

/// The focused section: the system's picture (from the theme) or its
/// covers fanned out, then its logo, facts and numbers.
private struct CabinetSectionInfo: View {
    let section: CabinetSection

    @Environment(\.cabinetTheme) private var installed
    @Environment(\.modelContext) private var modelContext
    @State private var stats: CabinetSectionStats?
    @State private var videoURL: URL?
    @AppStorage(GameHeaderMedia.previewsKey) private var playsPreviews = true
    @AppStorage("videoPreviewsMuted") private var isMuted = true
    @AppStorage(CabinetSystemsView.playsVideosKey) private var playsSystemVideos = false

    var body: some View {
        let theme = installed.theme
        HStack(spacing: 60) {
            art
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                if let logo = section.logo {
                    logo
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 440, maxHeight: theme.typography.titleSize * 2.6, alignment: .leading)
                        .accessibilityLabel(section.title)
                } else {
                    Text(theme.cased(section.title))
                        .font(theme.titleFont)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                if let facts = section.facts {
                    Text(verbatim: facts)
                        .font(theme.largeFont(.medium))
                        .foregroundStyle(theme.palette.secondaryText.color)
                }
                if theme.systems.showsStats, let stats {
                    statsGrid(stats, theme: theme)
                    if let last = stats.lastPlayed {
                        Text("Last played: \(last)")
                            .font(theme.bodyFont())
                            .foregroundStyle(theme.palette.secondaryText.color)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
        .task(id: section.selection) {
            // Browsing past a section doesn't count its games.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            stats = CabinetSectionStats(selection: section.selection, context: modelContext)
        }
        .task(id: [section.id.hashValue, playsSystemVideos ? 1 : 0, installed.theme.systems.playsVideo ? 1 : 0]) {
            videoURL = nil
            guard playsSystemVideos, installed.theme.systems.playsVideo,
                  let url = section.ownArt(.video), GameHeaderMedia.canPlay(url) else { return }
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { videoURL = url }
        }
    }

    /// Its video after a moment, else the system's own picture, then the
    /// theme's, then its covers.
    @ViewBuilder
    private var art: some View {
        if let videoURL {
            VideoPreviewView(url: videoURL, isMuted: isMuted)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: installed.theme.tiles.cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                .transition(.opacity)
        } else if let picture = (section.ownArt(.picture) ?? installed.systemPicture(for: section)).flatMap(SystemLogoCache.image(at:)) {
            Image(nsImage: picture)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
        } else if let covers = stats?.covers, !covers.isEmpty {
            CabinetCoverFan(covers: covers)
        }
    }

    private func statsGrid(_ stats: CabinetSectionStats, theme: CabinetTheme) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 12) {
            GridRow {
                stat(stats.games.formatted(), "Games", theme: theme)
                stat(stats.played.formatted(), "Played", theme: theme)
            }
            GridRow {
                stat(stats.favorites.formatted(), "Favorites", theme: theme)
                stat(stats.playtime > 0 ? SystemOverviewView.formattedPlaytime(stats.playtime) : "—", "Play Time", theme: theme)
            }
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey, theme: CabinetTheme) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(theme.font(size: theme.typography.titleSize * 0.7, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(theme.smallFont(.medium))
                .foregroundStyle(theme.palette.secondaryText.color)
                .textCase(.uppercase)
        }
    }
}

/// A few of the section's covers, fanned like cards in a hand.
private struct CabinetCoverFan: View {
    let covers: [Game.CoverRef]

    var body: some View {
        GeometryReader { geometry in
            let middle = Double(covers.count - 1) / 2
            // The fan's width: a cover, the offsets either side, and room
            // for the outer covers' tilt.
            let height = min(geometry.size.height * 0.85, geometry.size.width / (1.3 + middle * 0.44))
            ZStack {
                ForEach(Array(covers.enumerated()), id: \.element.url) { index, cover in
                    let offset = Double(index) - middle
                    GameCoverArtView(url: cover.url, title: cover.title, showBackground: false)
                        .frame(width: height * 0.75, height: height)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                        .rotationEffect(.degrees(offset * 8), anchor: .bottom)
                        .offset(x: offset * height * 0.22, y: abs(offset) * 12)
                        .zIndex(-abs(offset))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// What the systems level says about a section, counted once per focus.
struct CabinetSectionStats {
    var games = 0
    var played = 0
    var favorites = 0
    var playtime = 0.0
    var lastPlayed: String?
    /// Favorites and the most played first.
    var covers: [Game.CoverRef] = []

    @MainActor
    init(selection: LibrarySelection, context: ModelContext) {
        var games = (try? context.fetch(FetchDescriptor(predicate: GameGridView.selectionPredicate(selection)))) ?? []
        if selection == .recentlyAdded {
            games = Array(games.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }.prefix(GameGridView.recentlyAddedCount))
        }
        self.games = games.count
        for game in games {
            if game.playCount > 0 { played += 1 }
            if game.favorite { favorites += 1 }
            playtime += game.totalPlaytimeSeconds
        }
        lastPlayed = games.filter { $0.lastPlayedDate != nil }.max { $0.lastPlayedDate! < $1.lastPlayedDate! }?.title
        let ranked = games.filter { $0.coverArtPath != nil }
            .sorted { ($0.favorite ? 1 : 0, $0.playCount) > ($1.favorite ? 1 : 0, $1.playCount) }
        covers = ranked.prefix(5).compactMap { game in game.coverArtURL.map { Game.CoverRef(url: $0, title: game.title) } }
    }
}

extension Game {
    /// A cover to draw without holding on to the game.
    struct CoverRef: Hashable {
        let url: URL
        let title: String
    }
}

extension CabinetThemeStore.Installed {
    /// The theme's picture for a section, from its systems folder: named
    /// after the system's ROMs folder (or another of its short names),
    /// a collection's name, or all-games, favorites, recently-played and
    /// recently-added.
    func systemPicture(for section: CabinetSection) -> URL? {
        guard let folder else { return nil }
        let names: [String] = switch section.selection {
        case .allGames: ["all-games"]
        case .favorites: ["favorites"]
        case .recentlyPlayed: ["recently-played"]
        case .recentlyAdded: ["recently-added"]
        case .collection: [section.title]
        case .system(let id): (SystemTaxonomy.definition(for: id).map { [$0.batoceraShortName, $0.esdeShortName] + $0.otherShortNames } ?? []) + [id.rawValue]
        }
        let directory = folder.appending(path: theme.systems.artFolder, directoryHint: .isDirectory)
        for name in names {
            for ext in ["png", "jpg", "jpeg", "heic", "webp"] {
                let url = directory.appending(path: "\(name).\(ext)")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
}
