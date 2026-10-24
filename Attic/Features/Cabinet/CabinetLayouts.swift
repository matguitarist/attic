import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

// MARK: - Carousel

/// A row of big covers, the focused one centered and its details below.
struct CabinetCarouselLayout: View {
    let shelf: CabinetShelfContent

    @Environment(\.cabinetTheme) private var installed
    @State private var scrolledID: PersistentIdentifier?

    var body: some View {
        let theme = installed.theme
        // Explicit heights: a horizontal ScrollView in a stack grabs all
        // the height it's offered, which pushed the details (and the
        // header above) off screen.
        GeometryReader { geometry in
            let infoHeight = theme.typography.titleSize + theme.typography.bodySize * Double(4 + (theme.details.showsDescription ? theme.details.descriptionLines : 0)) * 1.4
            let room = max(180, geometry.size.height - infoHeight - 40)
            let coverHeight = max(180, min(room, geometry.size.height * theme.tiles.size))
            VStack(spacing: 24) {
                carousel(coverHeight: coverHeight, width: geometry.size.width)
                    .frame(height: coverHeight)
                CabinetGameInfo(game: shelf.focusedGame, alignment: .center)
                    .padding(.horizontal, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, 16)
        }
        .onChange(of: shelf.focusedID, initial: true) { old, id in
            withAnimation(old == nil ? nil : .snappy(duration: 0.25)) { scrolledID = id }
        }
        .onChange(of: shelf.games.count) { scrolledID = shelf.focusedID }
        .onChange(of: scrolledID) { _, id in
            // Trackpad/mouse scrolling moves focus too.
            if let id, id != shelf.focusedID, let game = shelf.games.first(where: { $0.persistentModelID == id }) {
                shelf.onFocus(game)
            }
        }
    }

    private func carousel(coverHeight: CGFloat, width: CGFloat) -> some View {
        let coverWidth = coverHeight * 0.75
        return ScrollView(.horizontal) {
            LazyHStack(spacing: installed.theme.tiles.spacing) {
                ForEach(shelf.games) { game in
                    CabinetTile(game: game, isFocused: shelf.isFocused(game))
                        .frame(width: coverWidth, height: coverHeight)
                        .id(game.persistentModelID)
                        .onTapGesture(count: 2) { shelf.onPlay(game) }
                        .onTapGesture { shelf.onFocus(game) }
                }
            }
            .scrollTargetLayout()
        }
        // Centers the first and last covers instead of pinning them to the
        // screen edges.
        .contentMargins(.horizontal, max(0, (width - coverWidth) / 2), for: .scrollContent)
        .scrollPosition(id: $scrolledID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        // `.never`, not `.hidden`: with "Show scroll bars: Always" set in
        // System Settings, `.hidden` still draws them.
        .scrollIndicators(.never)
    }
}

// MARK: - Cover Flow

/// The focused game's 2D box facing the screen in the middle, the others
/// to either side turned toward it, all standing over their reflections,
/// like iTunes's Cover Flow. With 3D boxes for the tiles' art, a game that
/// has one stands as its rendered box; the others turn their covers.
struct CabinetCoverFlowLayout: View {
    let shelf: CabinetShelfContent

    @Environment(\.cabinetTheme) private var installed
    /// Where a drag started, to move one game per step dragged.
    @State private var dragStart: Int?

    /// The reflection's height, of the cover's.
    static let reflection = 0.3
    /// The first cover beside the focused one, in cover widths from the
    /// middle.
    private static let firstStep = 0.78
    /// Between the next ones, in cover widths: turned covers overlap
    /// more than standing 3D boxes. The tiles' spacing adds points.
    private static let step = 0.3
    private static let boxStep = 0.55

    var body: some View {
        let theme = installed.theme
        GeometryReader { geometry in
            let infoHeight = theme.typography.titleSize + theme.typography.bodySize * Double(4 + (theme.details.showsDescription ? theme.details.descriptionLines : 0)) * 1.4
            let room = max(180, geometry.size.height - infoHeight - 40)
            let coverHeight = max(150, min(room / (1 + Self.reflection), geometry.size.height * theme.tiles.size))
            VStack(spacing: 8) {
                flow(coverHeight: coverHeight, width: geometry.size.width)
                    .frame(width: geometry.size.width, height: coverHeight * (1 + Self.reflection))
                CabinetGameInfo(game: shelf.focusedGame, alignment: .center)
                    .padding(.horizontal, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, 16)
        }
    }

    private func flow(coverHeight: CGFloat, width: CGFloat) -> some View {
        let coverWidth = coverHeight * 0.75
        let step = coverWidth * (installed.theme.tiles.art == .box3D ? Self.boxStep : Self.step) + installed.theme.tiles.spacing
        let games = shelf.games
        let focused = games.firstIndex { shelf.isFocused($0) } ?? 0
        // Only the covers on screen, and one more each side to slide in.
        let reach = Int(((width / 2 - coverWidth * Self.firstStep) / max(step, 1)).rounded(.up)) + 2
        let shown = max(0, focused - reach)...min(games.count - 1, max(0, focused + reach))
        let covers = shown.map { (offset: $0 - focused, game: games[$0]) }
        return ZStack(alignment: .top) {
            ForEach(covers, id: \.game.persistentModelID) { cover in
                let distance = CGFloat(abs(cover.offset))
                let x = cover.offset == 0 ? 0 : (coverWidth * Self.firstStep + (distance - 1) * step) * CGFloat(cover.offset.signum())
                CabinetCoverFlowItem(game: cover.game, offset: cover.offset, size: CGSize(width: coverWidth, height: coverHeight))
                    .offset(x: x)
                    // The middle on top, the others under their neighbors
                    // nearer it.
                    .zIndex(-Double(distance))
                    .onTapGesture(count: 2) { shelf.onPlay(cover.game) }
                    .onTapGesture { shelf.onFocus(cover.game) }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.3), value: shelf.focusedID)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    let start = dragStart ?? focused
                    dragStart = start
                    let target = min(max(start - Int((value.translation.width / max(step, 1)).rounded()), 0), games.count - 1)
                    if target != focused { shelf.onFocus(games[target]) }
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}

/// One game in the Cover Flow: its 2D box when focused, else its 3D box
/// standing or its cover turned toward the middle, over its reflection.
private struct CabinetCoverFlowItem: View {
    let game: Game
    /// From the focused game: negative to its left.
    let offset: Int
    let size: CGSize

    @Environment(\.cabinetTheme) private var installed
    /// Looked up once: the 3D box lives by file alone.
    @State private var box3DURL: URL?

    var body: some View {
        let theme = installed.theme
        let isFocused = offset == 0
        let standing = !isFocused && box3DURL != nil
        let side = Double(offset.signum())
        VStack(spacing: 2) {
            art
            art
                .scaleEffect(x: 1, y: -1)
                .frame(height: size.height * CabinetCoverFlowLayout.reflection, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .topTrailing) {
            if game.favorite && isFocused {
                Image(systemName: "star.fill")
                    .font(theme.largeFont())
                    .foregroundStyle(theme.palette.favorite.color)
                    .shadow(radius: 4)
                    .padding(10)
            }
        }
        // Further from the middle, darker: not see-through, as the covers
        // overlap.
        .brightness(isFocused ? 0 : -(1 - theme.tiles.unfocusedOpacity) * min(1, Double(abs(offset)) / 3))
        // A 3D box is drawn turned already: a little more toward the
        // middle is enough.
        .rotation3DEffect(.degrees(isFocused ? 0 : -side * (standing ? 22 : 55)), axis: (0, 1, 0), perspective: 0.6)
        // From the floor, so every cover stands on the same line.
        .scaleEffect(isFocused ? 1 : 1 / max(theme.tiles.focusScale, 0.1),
                     anchor: UnitPoint(x: 0.5, y: 1 / (1 + CabinetCoverFlowLayout.reflection)))
        .shadow(color: isFocused && theme.tiles.focusGlow ? theme.palette.accent.color.opacity(0.6) : .clear, radius: 24)
        .task(id: [game.persistentModelID.hashValue, theme.tiles.art.hashValue]) {
            box3DURL = theme.tiles.art == .box3D ? game.box3DURL : nil
        }
    }

    /// The cover and the 3D box both drawn, so moving in or out of the
    /// middle fades from one to the other instead of loading it then.
    private var art: some View {
        let standing = offset != 0 && box3DURL != nil
        return ZStack {
            GameCoverArtView(url: game.coverArtURL, title: game.title, showBackground: false, alignment: .bottom)
                .opacity(standing ? 0 : 1)
            if let box3DURL {
                GameCoverArtView(url: box3DURL, title: game.title, showBackground: false, alignment: .bottom)
                    .opacity(standing ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Hero

/// The focused game's art filling the screen (the theme's backdrop, faded
/// into the background), its logo, facts and description at the top left,
/// and a row of wide cards along the bottom, like the Apple TV's.
struct CabinetHeroLayout: View {
    let shelf: CabinetShelfContent

    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let theme = installed.theme
        GeometryReader { geometry in
            let cardHeight = max(120, geometry.size.height * theme.tiles.size)
            let cardWidth = cardHeight * 16 / 9
            // Room for the focused card to grow and cast its shadow.
            let growth = cardHeight * max(0, theme.tiles.focusScale - 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    if let game = shelf.focusedGame {
                        CabinetGameTitle(game: game, alignment: .leading, centersLogo: false,
                                         logoBox: CGSize(width: cardWidth, height: cardHeight * 0.6))
                            .id(game.persistentModelID)
                            .transition(.opacity)
                    }
                    CabinetGameInfo(game: shelf.focusedGame, alignment: .leading, showsTitle: false, inlineFacts: true)
                }
                .frame(maxWidth: max(480, geometry.size.width * 0.45), alignment: .leading)
                .padding(.horizontal, Self.margin)
                .padding(.top, 24)
                Spacer(minLength: 24)
                row(cardWidth: cardWidth, cardHeight: cardHeight)
                    .frame(height: cardHeight + growth + 48)
            }
        }
    }

    /// Off the screen's edges, as on the Apple TV.
    private static let margin: CGFloat = 80

    private func row(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: installed.theme.tiles.spacing) {
                    ForEach(shelf.games) { game in
                        CabinetTile(game: game, isFocused: shelf.isFocused(game), fillsArt: true)
                            .frame(width: cardWidth, height: cardHeight)
                            .id(game.persistentModelID)
                            .onTapGesture(count: 2) { shelf.onPlay(game) }
                            .onTapGesture { shelf.onFocus(game) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
            .scrollIndicators(.never)
            // Scrolls only as far as it takes to show the focused card, so
            // focus walks along the row and the row moves at its ends.
            .onChange(of: shelf.focusedID, initial: true) { old, id in
                withAnimation(old == nil ? nil : .snappy(duration: 0.25)) { proxy.scrollTo(id) }
            }
            .onChange(of: shelf.games.count) { proxy.scrollTo(shelf.focusedID) }
        }
    }
}

// MARK: - Grid

/// A grid of covers beside the focused game's picture and details, like
/// Steam's Big Picture.
struct CabinetGridLayout: View {
    let shelf: CabinetShelfContent
    @Binding var columns: Int

    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let tiles = installed.theme.tiles
        GeometryReader { geometry in
            let panelWidth = min(620, geometry.size.width * 0.36)
            let gridWidth = geometry.size.width - panelWidth - 40 * 3
            let tileHeight = max(120, geometry.size.height * tiles.size)
            let tileWidth = tileHeight * 0.75
            let columnCount = GridNavigation.columnCount(availableWidth: gridWidth, cellWidth: tileWidth, spacing: tiles.spacing)
            let details = installed.theme.details
            let panel = CabinetDetailsPanel(game: shelf.focusedGame)
                .frame(width: panelWidth)
                .padding(.vertical, 24)
            HStack(alignment: .top, spacing: 40) {
                if details.side == .leading { panel }
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: tiles.spacing), count: columnCount),
                                  spacing: tiles.spacing + (tiles.showsTitles ? 8 : 0)) {
                            ForEach(shelf.games) { game in
                                CabinetTile(game: game, isFocused: shelf.isFocused(game))
                                    .frame(width: tileWidth, height: tileHeight)
                                    .id(game.persistentModelID)
                                    .onTapGesture(count: 2) { shelf.onPlay(game) }
                                    .onTapGesture { shelf.onFocus(game) }
                            }
                        }
                        // Room for the focused tile to grow and glow.
                        .padding(tileHeight * max(0, tiles.focusScale - 1) / 2 + 24)
                    }
                    .scrollIndicators(.never)
                    .frame(width: gridWidth + 48)
                    .onChange(of: shelf.focusedID) { _, id in
                        withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    // A search or filter changing the games keeps the
                    // focused one in view.
                    .onChange(of: shelf.games.count) { proxy.scrollTo(shelf.focusedID, anchor: .center) }
                }
                .frame(maxWidth: .infinity)

                if details.side == .trailing { panel }
            }
            .padding(.horizontal, 40)
            .onChange(of: columnCount, initial: true) { _, count in columns = count }
        }
    }
}

/// The focused game's picture and details on a panel.
private struct CabinetDetailsPanel: View {
    let game: Game?

    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let theme = installed.theme
        VStack(alignment: .leading, spacing: 18) {
            if let game {
                if theme.details.media != .none {
                    CabinetMedia(game: game)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: theme.tiles.cornerRadius, style: .continuous))
                }
                let titleAtBottom = theme.details.titlePosition == .bottom
                CabinetGameInfo(game: game, alignment: .leading, showsTitle: !titleAtBottom)
                    .padding(.top, 10)
                Spacer(minLength: 24)
                if titleAtBottom {
                    CabinetGameTitle(game: game, alignment: .center, isLarge: true)
                        .id(game.persistentModelID)
                        .transition(.opacity)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.palette.surface.color, in: RoundedRectangle(cornerRadius: theme.tiles.cornerRadius + 8, style: .continuous))
    }
}

// MARK: - Wheel

/// A wheel of logos curving along the side, the focused one in the middle,
/// beside a screen playing its video, like CoinOps and HyperSpin.
struct CabinetWheelLayout: View {
    let shelf: CabinetShelfContent
    /// The screen in an arcade cabinet, its marquee above it.
    var drawsCabinet = false

    @Environment(\.cabinetTheme) private var installed
    @State private var scrolledID: PersistentIdentifier?

    /// Entries in view at once.
    private static let visibleEntries = 7.0

    var body: some View {
        GeometryReader { geometry in
            let wheelWidth = min(560, geometry.size.width * 0.36)
            let entryHeight = geometry.size.height / Self.visibleEntries
            HStack(spacing: 48) {
                screen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                wheel(entryHeight: entryHeight, height: geometry.size.height)
                    .frame(width: wheelWidth)
            }
            .padding(.leading, 60)
            .padding(.trailing, 70)
        }
        .onChange(of: shelf.focusedID, initial: true) { old, id in
            withAnimation(old == nil ? nil : .snappy(duration: 0.2)) { scrolledID = id }
        }
        .onChange(of: shelf.games.count) { scrolledID = shelf.focusedID }
        .onChange(of: scrolledID) { _, id in
            if let id, id != shelf.focusedID, let game = shelf.games.first(where: { $0.persistentModelID == id }) {
                shelf.onFocus(game)
            }
        }
    }

    /// The focused game's video or picture in a glowing frame, its details
    /// under it.
    private var screen: some View {
        let theme = installed.theme
        return VStack(spacing: 20) {
            Spacer(minLength: 0)
            if let game = shelf.focusedGame, drawsCabinet {
                CabinetArcadeCabinet(game: game)
                    .layoutPriority(-1)
                // The marquee shows the title.
                CabinetGameInfo(game: game, alignment: .center, showsDescription: false, showsTitle: false, inlineFacts: true)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let game = shelf.focusedGame {
                if theme.details.media != .none {
                    CabinetMedia(game: game)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: theme.tiles.cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: theme.tiles.cornerRadius, style: .continuous)
                                .strokeBorder(theme.palette.accent.color, lineWidth: 3)
                        }
                        .shadow(color: theme.tiles.focusGlow ? theme.palette.accent.color.opacity(0.6) : .clear, radius: 30)
                        .layoutPriority(-1)
                }
                CabinetGameInfo(game: game, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func wheel(entryHeight: CGFloat, height: CGFloat) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(shelf.games) { game in
                    HStack(spacing: 12) {
                        if game.favorite {
                            Image(systemName: "star.fill")
                                .font(installed.theme.largeFont())
                                .foregroundStyle(installed.theme.palette.favorite.color)
                                .shadow(radius: 4)
                        }
                        CabinetTile(game: game, isFocused: shelf.isFocused(game), showsFavoriteBadge: false)
                    }
                        .frame(height: entryHeight * installed.theme.tiles.size)
                        .frame(maxWidth: .infinity)
                        .frame(height: entryHeight)
                        .contentShape(Rectangle())
                        .id(game.persistentModelID)
                        .onTapGesture(count: 2) { shelf.onPlay(game) }
                        .onTapGesture { shelf.onFocus(game) }
                        // Entries swing away from the screen the further
                        // they are from the middle, along an arc.
                        .visualEffect { content, proxy in
                            let distance = (proxy.frame(in: .scrollView).midY - height / 2) / max(1, height / 2)
                            return content
                                .offset(x: min(1, distance * distance) * 60)
                                .scaleEffect(1 - min(1, abs(distance)) * 0.15)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, max(0, (height - entryHeight) / 2), for: .scrollContent)
        .scrollPosition(id: $scrolledID, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.never)
    }
}

// MARK: - List

/// A list of titles beside the focused game's art, picture and details,
/// like EmulationStation's gamelist. The art is the tiles' `art`.
struct CabinetListLayout: View {
    let shelf: CabinetShelfContent

    @Environment(\.cabinetTheme) private var installed
    @State private var scrolledID: PersistentIdentifier?

    var body: some View {
        let theme = installed.theme
        GeometryReader { geometry in
            let rowHeight = theme.typography.bodySize * 2.3
            HStack(alignment: .top, spacing: 40) {
                list(rowHeight: rowHeight, height: geometry.size.height)
                    .frame(width: min(640, geometry.size.width * 0.42))
                    .background(theme.palette.surface.color.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: theme.tiles.cornerRadius + 6, style: .continuous))

                if let game = shelf.focusedGame {
                    CabinetListDetails(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        .onChange(of: shelf.focusedID, initial: true) { old, id in
            withAnimation(old == nil ? nil : .snappy(duration: 0.15)) { scrolledID = id }
        }
        .onChange(of: shelf.games.count) { scrolledID = shelf.focusedID }
        .onChange(of: scrolledID) { _, id in
            if let id, id != shelf.focusedID, let game = shelf.games.first(where: { $0.persistentModelID == id }) {
                shelf.onFocus(game)
            }
        }
    }

    private func list(rowHeight: CGFloat, height: CGFloat) -> some View {
        let theme = installed.theme
        return ScrollView(.vertical) {
            LazyVStack(spacing: theme.tiles.spacing) {
                ForEach(shelf.games) { game in
                    let isFocused = shelf.isFocused(game)
                    HStack(spacing: 10) {
                        if game.favorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(theme.palette.favorite.color)
                        }
                        Text(theme.cased(game.title))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let year = game.releaseYear {
                            Text(verbatim: String(year))
                                .foregroundStyle(isFocused ? theme.palette.background.color.opacity(0.8) : theme.palette.secondaryText.color)
                        }
                    }
                    .font(theme.bodyFont(isFocused ? .semibold : .regular))
                    .foregroundStyle(isFocused ? theme.palette.background.color : theme.palette.text.color)
                    .padding(.horizontal, 16)
                    .frame(height: rowHeight)
                    .background(isFocused ? theme.palette.accent.color : .clear,
                                in: RoundedRectangle(cornerRadius: theme.tiles.cornerRadius, style: .continuous))
                    .contentShape(Rectangle())
                    .id(game.persistentModelID)
                    .onTapGesture(count: 2) { shelf.onPlay(game) }
                    .onTapGesture { shelf.onFocus(game) }
                }
            }
            .scrollTargetLayout()
            .padding(8)
        }
        .contentMargins(.vertical, max(0, (height - rowHeight) / 2 - 20), for: .scrollContent)
        .scrollPosition(id: $scrolledID, anchor: .center)
        .scrollIndicators(.never)
    }
}

/// The list's other side: the game's art beside its picture, its details
/// below.
private struct CabinetListDetails: View {
    let game: Game

    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let theme = installed.theme
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                CabinetTile(game: game, isFocused: true)
                    .aspectRatio(0.75, contentMode: .fit)
                    .frame(maxWidth: 300, maxHeight: 400)
                if theme.details.media != .none {
                    CabinetMedia(game: game)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: theme.tiles.cornerRadius, style: .continuous))
                        .frame(maxHeight: 400)
                }
            }
            CabinetGameInfo(game: game, alignment: .leading)
        }
        .id(game.persistentModelID)
    }
}
