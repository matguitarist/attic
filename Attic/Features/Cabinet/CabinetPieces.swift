import SwiftUI
import AtticModels
import AtticPersistence

/// One game in a layout: its cover, screenshot or logo per the theme,
/// grown and lit when focused.
struct CabinetTile: View {
    let game: Game
    let isFocused: Bool
    /// The star in the corner; the wheel draws its own beside the logo.
    var showsFavoriteBadge = true

    @Environment(\.cabinetTheme) private var installed
    /// Looked up once: the logo and 3D box live by file alone.
    @State private var logoURL: URL?
    @State private var box3DURL: URL?

    var body: some View {
        let theme = installed.theme
        let tiles = theme.tiles
        let shape = RoundedRectangle(cornerRadius: tiles.cornerRadius, style: .continuous)
        VStack(spacing: 8) {
            art(theme)
                .padding(tiles.showsBackground ? 8 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tiles.showsBackground ? theme.palette.surface.color : .clear, in: shape)
                .clipShape(shape)
                .overlay {
                    if tiles.focusRing && isFocused {
                        shape.strokeBorder(theme.palette.accent.color, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if game.favorite && showsFavoriteBadge {
                        Image(systemName: "star.fill")
                            .font(theme.largeFont())
                            .foregroundStyle(theme.palette.favorite.color)
                            .shadow(radius: 4)
                            .padding(10)
                    }
                }
            if tiles.showsTitles && tiles.art != .logo {
                Text(theme.cased(game.title))
                    .font(theme.smallFont(isFocused ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isFocused ? theme.palette.text.color : theme.palette.secondaryText.color)
            }
        }
        .scaleEffect(isFocused ? 1 : 1 / max(tiles.focusScale, 0.1))
        .opacity(isFocused ? 1 : tiles.unfocusedOpacity)
        .shadow(color: glowColor(theme), radius: isFocused ? 24 : 0, y: tiles.focusGlow ? 0 : 16)
        .animation(.snappy(duration: 0.25), value: isFocused)
        .task(id: [game.persistentModelID.hashValue, tiles.art.hashValue]) {
            logoURL = tiles.art == .logo ? game.logoURL : nil
            box3DURL = tiles.art == .box3D ? game.box3DURL : nil
        }
    }

    @ViewBuilder
    private func art(_ theme: CabinetTheme) -> some View {
        switch theme.tiles.art {
        case .cover:
            GameCoverArtView(url: game.coverArtURL, title: game.title, showBackground: false)
        case .box3D:
            GameCoverArtView(url: box3DURL ?? game.coverArtURL, title: game.title, showBackground: false)
        case .screenshot:
            GameCoverArtView(url: game.titleScreenURL ?? game.coverArtURL, title: game.title, showBackground: false)
        case .logo:
            if let logoURL {
                GameCoverArtView(url: logoURL, title: game.title, showBackground: false)
            } else {
                // No logo: the title, set like one.
                Text(theme.cased(game.title))
                    .font(theme.font(size: theme.typography.titleSize * 0.9, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(isFocused ? theme.palette.text.color : theme.palette.secondaryText.color)
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }
        }
    }

    private func glowColor(_ theme: CabinetTheme) -> Color {
        guard isFocused else { return .clear }
        return theme.tiles.focusGlow ? theme.palette.accent.color.opacity(0.65) : .black.opacity(0.6)
    }
}

/// The focused game's picture per the theme, its video playing over it
/// after a moment when the theme and Settings allow.
struct CabinetMedia: View {
    let game: Game

    @Environment(\.cabinetTheme) private var installed
    @AppStorage(GameHeaderMedia.previewsKey) private var playsPreviews = true
    @AppStorage("videoPreviewsMuted") private var isMuted = true
    @State private var videoURL: URL?

    var body: some View {
        let details = installed.theme.details
        ZStack {
            Color.black
            GameCoverArtView(url: CabinetArt.url(for: game, details.media), title: game.title, showBackground: false)
            if let videoURL {
                VideoPreviewView(url: videoURL, isMuted: isMuted)
                    .transition(.opacity)
                    .id(videoURL)
            }
        }
        .task(id: [game.persistentModelID.hashValue, details.playsVideo ? 1 : 0, playsPreviews ? 1 : 0]) {
            videoURL = nil
            guard details.playsVideo, playsPreviews, let url = game.previewVideoURL, GameHeaderMedia.canPlay(url) else { return }
            // Browsing past a game doesn't start its video.
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { videoURL = url }
        }
    }
}

/// The game's logo when the theme shows logos and it has one, else its
/// title. A logo gets room around it and sits centered in a panel.
struct CabinetGameTitle: View {
    let game: Game
    let alignment: HorizontalAlignment
    /// At a panel's foot, where there's room for a bigger logo.
    var isLarge = false
    /// A logo sits centered, even in a leading column, except on the
    /// game page where it heads the facts.
    var centersLogo = true

    @Environment(\.cabinetTheme) private var installed
    @State private var logoURL: URL?

    var body: some View {
        let theme = installed.theme
        Group {
            if theme.details.showsLogo, let logoURL {
                GameCoverArtView(url: logoURL, title: game.title, showBackground: false)
                    .frame(maxWidth: isLarge ? 500 : 420, maxHeight: theme.typography.titleSize * (isLarge ? 3.4 : 2.4))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: centersLogo ? .center : .leading)
            } else {
                Text(theme.cased(game.title))
                    .font(theme.titleFont)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            }
        }
        .task(id: game.persistentModelID) {
            logoURL = theme.details.showsLogo ? game.logoURL : nil
        }
    }
}

/// The focused game's title (or logo), facts, state and description, as
/// much as the theme shows. Centered, the facts run on one line; along
/// the side, each gets a line of its own.
struct CabinetGameInfo: View {
    let game: Game?
    let alignment: HorizontalAlignment
    /// The game page shows the description itself, scrollable.
    var showsDescription = true
    /// A panel can put the title elsewhere (`Details.titlePosition`).
    var showsTitle = true
    /// The game page's: developer, publisher, play time, last played,
    /// under a logo kept to the left.
    var showsMoreFacts = false

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        if let game {
            let theme = installed.theme
            let textAlignment: TextAlignment = alignment == .center ? .center : .leading
            VStack(alignment: alignment, spacing: alignment == .center ? 10 : 16) {
                if showsTitle {
                    CabinetGameTitle(game: game, alignment: alignment, centersLogo: !showsMoreFacts)
                }

                if theme.details.showsMetadata {
                    if alignment == .center {
                        Text(facts(for: game).map(\.value).joined(separator: "  ·  "))
                            .font(theme.bodyFont())
                            .foregroundStyle(theme.palette.secondaryText.color)
                            .multilineTextAlignment(textAlignment)
                    } else {
                        factRows(for: game, theme: theme)
                    }
                }

                if launchCoordinator.state == .running(gameID: game.persistentModelID) {
                    Label("Playing", systemImage: "gamecontroller.fill")
                        .font(theme.bodyFont(.semibold))
                        .foregroundStyle(.green)
                } else if case .failed(let message) = launchCoordinator.state {
                    Text(message)
                        .font(theme.bodyFont())
                        .foregroundStyle(.red)
                } else if showsDescription, theme.details.showsDescription, let description = game.gameDescription {
                    Text(description)
                        .font(theme.bodyFont())
                        .foregroundStyle(theme.palette.secondaryText.color)
                        .lineLimit(theme.details.descriptionLines)
                        .multilineTextAlignment(textAlignment)
                        .frame(maxWidth: 1000, alignment: alignment == .center ? .center : .leading)
                }
            }
            .id(game.persistentModelID)
            .transition(.opacity)
        }
    }

    private func factRows(for game: Game, theme: CabinetTheme) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(facts(for: game), id: \.symbol) { fact in
                GridRow {
                    Image(systemName: fact.symbol)
                        .foregroundStyle(theme.palette.accent.color)
                        .frame(width: theme.typography.bodySize * 1.3)
                    Text(fact.label)
                        .foregroundStyle(theme.palette.secondaryText.color)
                    Text(verbatim: fact.value)
                        .foregroundStyle(theme.palette.text.color)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(theme.bodyFont())
    }

    private struct Fact {
        let symbol: String
        let label: String
        let value: String
    }

    private func facts(for game: Game) -> [Fact] {
        var facts: [Fact] = []
        if let system = game.system?.displayName {
            facts.append(Fact(symbol: "gamecontroller", label: String(localized: "System"), value: system))
        }
        if let year = game.releaseDate.map({ Calendar.current.component(.year, from: $0) }) {
            facts.append(Fact(symbol: "calendar", label: String(localized: "Year"), value: String(year)))
        }
        if let genre = game.genre {
            facts.append(Fact(symbol: "tag", label: String(localized: "Genre"), value: genre))
        }
        // `players` is free text from scrapers ("1", "1-2", "1-4"), so it
        // can't drive a plural — label it instead.
        if let players = game.players {
            facts.append(Fact(symbol: "person.2", label: String(localized: "Players"),
                              value: alignment == .center ? String(localized: "Players: \(players)") : players))
        }
        if showsMoreFacts {
            if let developer = game.developer {
                facts.append(Fact(symbol: "hammer", label: String(localized: "Developer"), value: developer))
            }
            if let publisher = game.publisher, publisher != game.developer {
                facts.append(Fact(symbol: "building.2", label: String(localized: "Publisher"), value: publisher))
            }
        }
        if game.playCount > 0 {
            let value = if alignment == .center {
                String(localized: "Played \(game.playCount)×")
            } else if showsMoreFacts {
                String(localized: "\(game.playCount)× · \(SystemOverviewView.formattedPlaytime(game.totalPlaytimeSeconds))")
            } else {
                String(localized: "\(game.playCount)×")
            }
            facts.append(Fact(symbol: "clock.arrow.circlepath", label: String(localized: "Played"), value: value))
        }
        if showsMoreFacts, let last = game.lastPlayedDate {
            facts.append(Fact(symbol: "clock", label: String(localized: "Last Played"),
                              value: last.formatted(.relative(presentation: .named))))
        }
        return facts
    }
}
