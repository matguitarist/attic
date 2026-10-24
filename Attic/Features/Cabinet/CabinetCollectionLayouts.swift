import SwiftUI
import SwiftData
import ImageIO
import AtticModels
import AtticPersistence

// MARK: - Shelf

/// The games standing in rows on shelves, like a collection on a wall,
/// the focused one pulled forward, its details below. With `box3D`
/// tiles, games with a 3D box stand as it.
struct CabinetShelfLayout: View {
    let shelf: CabinetShelfContent
    @Binding var columns: Int

    @Environment(\.cabinetTheme) private var installed

    @State private var topRow = 0

    /// Off the screen's edges, past the ends of the planks.
    private static let margin: CGFloat = 60
    /// The plank's thickness, in points.
    private static let plank: CGFloat = 18
    /// Between a plank and the boxes on the one above it, besides the
    /// room the focused box grows into.
    private static let gap: CGFloat = 18
    /// A box's room, its width over its height: a 3D box's, with a 2D
    /// box a touch shorter in it.
    private static let boxAspect: CGFloat = 0.7

    var body: some View {
        let theme = installed.theme
        let tiles = theme.tiles
        GeometryReader { geometry in
            let infoHeight = theme.typography.titleSize + theme.typography.bodySize * Double(3 + (theme.details.showsDescription ? theme.details.descriptionLines : 0)) * 1.4
            let shelvesHeight = max(200, geometry.size.height - infoHeight - 12)
            let growth = max(0, tiles.focusScale - 1)
            // As many whole shelves as fit at about the theme's size, then
            // the boxes sized to fill them: no shelf cut at the top or
            // bottom.
            let wanted = max(110, geometry.size.height * tiles.size)
            let visibleRows = max(1, Int(shelvesHeight / (wanted * (1 + growth) + Self.gap + Self.plank)))
            let boxHeight = (shelvesHeight / CGFloat(visibleRows) - Self.gap - Self.plank) / (1 + growth)
            let boxWidth = boxHeight * Self.boxAspect
            let columnCount = max(1, GridNavigation.columnCount(availableWidth: geometry.size.width - 2 * Self.margin - 32,
                                                                cellWidth: boxWidth, spacing: tiles.spacing))
            // Full rows centered on the planks; the last starts where they do.
            let rowWidth = CGFloat(columnCount) * boxWidth + CGFloat(columnCount - 1) * tiles.spacing
            let rows = stride(from: 0, to: shelf.games.count, by: columnCount)
                .map { $0..<min($0 + columnCount, shelf.games.count) }
            let focusedRow = shelf.games.firstIndex { shelf.isFocused($0) }.map { $0 / columnCount }
            VStack(spacing: 12) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows.indices, id: \.self) { row in
                                shelfRow(rows[row], boxWidth: boxWidth, boxHeight: boxHeight, rowWidth: rowWidth)
                                    // Room for the focused box to grow.
                                    .padding(.top, boxHeight * growth + Self.gap)
                                    .id(row)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: shelvesHeight)
                    // A shelf at a time, only once focus leaves the ones in
                    // view, so they're never cut.
                    .onChange(of: focusedRow, initial: true) { old, row in
                        guard let row else { return }
                        if row < topRow { topRow = row }
                        if row >= topRow + visibleRows { topRow = row - visibleRows + 1 }
                        withAnimation(old == nil ? nil : .snappy(duration: 0.25)) { proxy.scrollTo(topRow, anchor: .top) }
                    }
                    .onChange(of: visibleRows) { proxy.scrollTo(topRow, anchor: .top) }
                    .onChange(of: shelf.games.count) {
                        if let focusedRow { topRow = max(0, focusedRow - visibleRows + 1) }
                        proxy.scrollTo(topRow, anchor: .top)
                    }
                }
                CabinetGameInfo(game: shelf.focusedGame, alignment: .center, inlineFacts: true)
                    .padding(.horizontal, 60)
                    .frame(height: infoHeight, alignment: .top)
            }
            .onChange(of: columnCount, initial: true) { _, count in columns = count }
        }
    }

    private func shelfRow(_ range: Range<Int>, boxWidth: CGFloat, boxHeight: CGFloat, rowWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: installed.theme.tiles.spacing) {
                ForEach(shelf.games[range]) { game in
                    CabinetShelfBox(game: game, isFocused: shelf.isFocused(game))
                        .frame(width: boxWidth, height: boxHeight)
                        .zIndex(shelf.isFocused(game) ? 1 : 0)
                        .onTapGesture(count: 2) { shelf.onPlay(game) }
                        .onTapGesture { shelf.onFocus(game) }
                }
            }
            .frame(width: rowWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            plank
                .padding(.horizontal, Self.margin)
        }
    }

    /// A plank in the surface color, lit along its front edge.
    private var plank: some View {
        let surface = installed.theme.palette.surface.color
        return ZStack(alignment: .top) {
            Color.black
            LinearGradient(colors: [surface, surface.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(height: 1.5)
        }
        .frame(height: Self.plank)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 10, y: 8)
    }
}

/// One game on the shelf, standing on its plank.
private struct CabinetShelfBox: View {
    let game: Game
    let isFocused: Bool

    @Environment(\.cabinetTheme) private var installed
    /// Looked up once: the 3D box lives by file alone.
    @State private var box3DURL: URL?

    var body: some View {
        let theme = installed.theme
        let tiles = theme.tiles
        GameCoverArtView(url: box3DURL ?? game.coverArtURL, title: game.title, showBackground: false, alignment: .bottom)
            .overlay(alignment: .topTrailing) {
                if game.favorite {
                    Image(systemName: "star.fill")
                        .font(theme.largeFont())
                        .foregroundStyle(theme.palette.favorite.color)
                        .shadow(radius: 4)
                        .padding(8)
                }
            }
            // Darker, not see-through, so the shelf doesn't show through.
            .brightness(isFocused ? 0 : -(1 - tiles.unfocusedOpacity))
            // From the plank, so it's pulled forward rather than lifted.
            .scaleEffect(isFocused ? 1 : 1 / max(tiles.focusScale, 0.1), anchor: .bottom)
            .shadow(color: isFocused && tiles.focusGlow ? theme.palette.accent.color.opacity(0.6) : .black.opacity(isFocused ? 0.7 : 0.4),
                    radius: isFocused ? 22 : 5, y: isFocused ? 10 : 2)
            .animation(.snappy(duration: 0.25), value: isFocused)
            .task(id: [game.persistentModelID.hashValue, tiles.art.hashValue]) {
                box3DURL = tiles.art == .box3D ? game.box3DURL : nil
            }
    }
}

// MARK: - Unboxed

/// The focused game's 2D box, its disc sliding out and spinning or its
/// cartridge rising from it, beside its logo and details, over a row of
/// the others along the bottom.
struct CabinetUnboxedLayout: View {
    let shelf: CabinetShelfContent

    @Environment(\.cabinetTheme) private var installed

    /// Off the screen's edges.
    private static let margin: CGFloat = 60

    var body: some View {
        let theme = installed.theme
        GeometryReader { geometry in
            let tileHeight = max(90, geometry.size.height * theme.tiles.size)
            let tileWidth = tileHeight * 0.75
            // Room for the focused tile to grow and cast its shadow.
            let growth = tileHeight * max(0, theme.tiles.focusScale - 1)
            VStack(spacing: 0) {
                HStack(spacing: 48) {
                    if let game = shelf.focusedGame {
                        CabinetUnboxedGame(game: game)
                            .id(game.persistentModelID)
                            .transition(.opacity)
                            .frame(width: geometry.size.width * 0.44)
                        VStack(alignment: .leading, spacing: 16) {
                            CabinetGameTitle(game: game, alignment: .leading, centersLogo: false)
                            CabinetGameInfo(game: game, alignment: .leading, showsTitle: false)
                        }
                        .id(game.persistentModelID)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Self.margin)
                .padding(.vertical, 16)
                .frame(maxHeight: .infinity)
                row(tileWidth: tileWidth, tileHeight: tileHeight)
                    .frame(height: tileHeight + growth + 40)
            }
            .animation(.easeInOut(duration: 0.2), value: shelf.focusedID)
        }
    }

    private func row(tileWidth: CGFloat, tileHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: installed.theme.tiles.spacing) {
                    ForEach(shelf.games) { game in
                        CabinetTile(game: game, isFocused: shelf.isFocused(game))
                            .frame(width: tileWidth, height: tileHeight)
                            .id(game.persistentModelID)
                            .onTapGesture(count: 2) { shelf.onPlay(game) }
                            .onTapGesture { shelf.onFocus(game) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
            .scrollIndicators(.never)
            .onChange(of: shelf.focusedID, initial: true) { old, id in
                withAnimation(old == nil ? nil : .snappy(duration: 0.25)) { proxy.scrollTo(id) }
            }
            .onChange(of: shelf.games.count) { proxy.scrollTo(shelf.focusedID) }
        }
    }
}

/// A game's 2D box with what it came on coming out of it: a disc or a
/// board sliding out to the right (a disc then spinning), a cartridge
/// rising from the top. Only the box when there's no picture of it.
private struct CabinetUnboxedGame: View {
    let game: Game

    @Environment(\.cabinetTheme) private var installed
    @State private var mediumURL: URL?
    @State private var isOut = false
    /// The box picture's width over its height: a HuCard's or a SNES box
    /// lies wide, most stand tall.
    @State private var boxAspect: CGFloat = 0.75

    /// The medium, of the box's shorter side: small enough to hide behind
    /// it before it comes out.
    private static let mediumScale: CGFloat = 0.78
    /// How much of the medium comes out past the box's edge.
    private static let outShare: CGFloat = 0.7

    var body: some View {
        let medium = PhysicalMedium.of(CanonicalSystemID(game.systemCanonicalID))
        let rises = medium == .cartridge
        GeometryReader { geometry in
            let hasMedium = mediumURL != nil
            let out = hasMedium ? Self.outShare * Self.mediumScale * min(boxAspect, 1) : 0
            // The box as it's drawn, with room for the medium beside it or
            // above it.
            let boxHeight = rises
                ? min(geometry.size.height * 0.92 / (1 + out), geometry.size.width / boxAspect)
                : min(geometry.size.height * 0.9, geometry.size.width / (boxAspect + out))
            let boxWidth = boxHeight * boxAspect
            let mediumSize = min(boxWidth, boxHeight) * Self.mediumScale
            // Out past the box's edge by `outShare` of its size.
            let travel = (rises ? boxHeight : boxWidth) / 2 + mediumSize * (Self.outShare - 0.5)
            ZStack {
                if let mediumURL {
                    mediumPicture(mediumURL, spins: medium == .disc && isOut)
                        .frame(width: mediumSize, height: mediumSize)
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                        // Hidden until it comes out, so it never shows
                        // around a box it's bigger than.
                        .opacity(isOut ? 1 : 0)
                        .offset(x: isOut && !rises ? travel : 0, y: isOut && rises ? -travel : 0)
                }
                GameCoverArtView(url: game.coverArtURL, title: game.title, showBackground: false)
                    .frame(width: boxWidth, height: boxHeight)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 10)
            }
            // The box and its medium centered together.
            .offset(x: rises ? 0 : -mediumSize * Self.outShare / 2 * (hasMedium ? 1 : 0),
                    y: rises ? mediumSize * Self.outShare / 2 * (hasMedium ? 1 : 0) : 0)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: game.persistentModelID) {
            boxAspect = CabinetGamePage.aspectRatio(of: game.coverArtURL) ?? 0.75
            guard installed.theme.details.showsPhysicalMedia, medium != nil, let url = game.physicalMediaURL else { return }
            mediumURL = url
            // Browsing past a game doesn't take its disc out.
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.7, bounce: 0.2)) { isOut = true }
        }
    }

    @ViewBuilder
    private func mediumPicture(_ url: URL, spins: Bool) -> some View {
        let picture = GameCoverArtView(url: url, title: game.title, showBackground: false)
        if spins {
            TimelineView(.animation) { context in
                picture.rotationEffect(.degrees((context.date.timeIntervalSinceReferenceDate * 30).truncatingRemainder(dividingBy: 360)))
            }
        } else {
            picture
        }
    }
}

// MARK: - Arcade cabinet

/// An upright arcade cabinet around the focused game, for the wheel's
/// screen: its marquee lit at the top (else its logo or title), its video
/// in the screen framed by its bezel, a control panel below.
struct CabinetArcadeCabinet: View {
    let game: Game

    @Environment(\.cabinetTheme) private var installed
    @State private var marqueeURL: URL?
    @State private var logoURL: URL?
    @State private var bezel: (url: URL, window: BezelWindow)?

    var body: some View {
        let theme = installed.theme
        GeometryReader { geometry in
            let screenAspect = bezel?.window.aspect ?? 4 / 3
            // The cabinet's parts in widths: marquee, screen, panel, and
            // the body's padding around them.
            let height = 0.22 + 1 / screenAspect + 0.26 + 0.12
            let width = min(geometry.size.width / 1.1, geometry.size.height / height)
            VStack(spacing: width * 0.03) {
                marquee(theme)
                    .frame(width: width * 0.96, height: width * 0.22)
                screen(theme)
                    .frame(width: width, height: width / screenAspect)
                CabinetControlPanel()
                    .frame(width: width * 1.04, height: width * 0.26)
            }
            .padding(width * 0.03)
            .background {
                RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                    .fill(theme.palette.surface.color)
                    // The T-molding along the cabinet's edge, glowing.
                    .overlay {
                        RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                            .strokeBorder(theme.palette.accent.color, lineWidth: max(3, width * 0.008))
                    }
                    .shadow(color: theme.tiles.focusGlow ? theme.palette.accent.color.opacity(0.5) : .black.opacity(0.6), radius: 30)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: game.persistentModelID) {
            marqueeURL = game.marqueeURL
            logoURL = marqueeURL == nil ? game.logoURL : nil
            bezel = nil
            guard let url = game.bezelURL, let window = await BezelWindow.of(url) else { return }
            withAnimation(.easeInOut(duration: 0.25)) { bezel = (url, window) }
        }
    }

    /// Lit from behind: the marquee, else the logo or title glowing on
    /// black.
    private func marquee(_ theme: CabinetTheme) -> some View {
        ZStack {
            Color.black
            if let marqueeURL {
                GameCoverArtView(url: marqueeURL, title: game.title, showBackground: false)
            } else if let logoURL {
                GameCoverArtView(url: logoURL, title: game.title, showBackground: false)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .shadow(color: theme.palette.accent.color.opacity(0.8), radius: 12)
            } else {
                Text(theme.cased(game.title))
                    .font(theme.titleFont)
                    .foregroundStyle(theme.palette.text.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 24)
                    .shadow(color: theme.palette.accent.color, radius: 12)
            }
            // The tube behind it, brightest in the middle.
            LinearGradient(colors: [.white.opacity(0.22), .clear, .white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                .blendMode(.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: theme.palette.accent.color.opacity(0.45), radius: 16)
    }

    /// The game's picture or video, through its bezel's window when it
    /// has one, else on a rounded tube.
    @ViewBuilder
    private func screen(_ theme: CabinetTheme) -> some View {
        if let bezel {
            GeometryReader { geometry in
                let window = bezel.window.rect
                ZStack {
                    Color.black
                    CabinetMedia(game: game)
                        .frame(width: geometry.size.width * window.width, height: geometry.size.height * window.height)
                        .position(x: geometry.size.width * window.midX, y: geometry.size.height * window.midY)
                    GameCoverArtView(url: bezel.url, title: game.title, showBackground: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            ZStack {
                Color.black
                CabinetMedia(game: game)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(10)
                // Glare on the glass.
                LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .topLeading, endPoint: .center)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// A joystick and two rows of buttons on a panel sloping toward you.
private struct CabinetControlPanel: View {
    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        let palette = installed.theme.palette
        GeometryReader { geometry in
            let size = geometry.size
            let button = size.height * 0.24
            ZStack {
                CabinetPanelShape()
                    .fill(LinearGradient(colors: [palette.surface.color, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .overlay { CabinetPanelShape().stroke(palette.accent.color.opacity(0.7), lineWidth: 2) }
                HStack(spacing: size.width * 0.12) {
                    joystick(size: size.height, color: palette.accent.color)
                    VStack(spacing: button * 0.4) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: button * 0.45) {
                                ForEach(0..<3, id: \.self) { column in
                                    Circle()
                                        .fill((row + column).isMultiple(of: 2) ? palette.accent.color : palette.favorite.color)
                                        .overlay { Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center)) }
                                        .frame(width: button, height: button)
                                        .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
                                }
                            }
                            .offset(x: CGFloat(row) * button * 0.35)
                        }
                    }
                }
                .padding(.top, size.height * 0.08)
            }
        }
    }

    private func joystick(size: CGFloat, color: Color) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.black.opacity(0.85))
                .frame(width: size * 0.07, height: size * 0.42)
                .offset(y: size * 0.18)
            Circle()
                .fill(color)
                .overlay { Circle().fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .center)) }
                .frame(width: size * 0.3, height: size * 0.3)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 3)
        }
        .frame(height: size * 0.6)
    }
}

/// Wider at the front than at the back, as a panel seen from above.
private struct CabinetPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.04
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The see-through window in a bezel's picture, where the game shows,
/// found by walking out from its middle while the pixels are clear.
struct BezelWindow: Sendable {
    /// Of the picture's size, 0 to 1.
    let rect: CGRect
    /// The picture's width over its height.
    let aspect: CGFloat

    @MainActor private static var found: [URL: BezelWindow] = [:]

    /// Nil for a picture with no clear middle: not a bezel.
    @MainActor static func of(_ url: URL) async -> BezelWindow? {
        if let window = found[url] { return window }
        let window = await Task.detached(priority: .userInitiated) { measure(url) }.value
        if let window { found[url] = window }
        return window
    }

    nonisolated static func measure(_ url: URL) -> BezelWindow? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Rows run top to bottom in memory.
        func isClear(_ x: Int, _ y: Int) -> Bool { alpha[y * width + x] < 40 }
        let middleX = width / 2, middleY = height / 2
        guard isClear(middleX, middleY) else { return nil }
        var left = middleX, right = middleX, top = middleY, bottom = middleY
        while left > 0 && isClear(left - 1, middleY) { left -= 1 }
        while right < width - 1 && isClear(right + 1, middleY) { right += 1 }
        while top > 0 && isClear(middleX, top - 1) { top -= 1 }
        while bottom < height - 1 && isClear(middleX, bottom + 1) { bottom += 1 }
        let w = CGFloat(width), h = CGFloat(height)
        return BezelWindow(rect: CGRect(x: CGFloat(left) / w, y: CGFloat(top) / h,
                                        width: CGFloat(right - left + 1) / w, height: CGFloat(bottom - top + 1) / h),
                           aspect: w / h)
    }
}
