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
            HStack(alignment: .top, spacing: 40) {
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
                }
                .frame(maxWidth: .infinity)

                CabinetDetailsPanel(game: shelf.focusedGame)
                    .frame(width: panelWidth)
                    .padding(.vertical, 24)
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
                CabinetGameInfo(game: game, alignment: .leading)
            }
            Spacer(minLength: 0)
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
            if let game = shelf.focusedGame {
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
                    CabinetTile(game: game, isFocused: shelf.isFocused(game))
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
