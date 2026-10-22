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
    /// Wide cards fill with their art, cropping it, rather than letterbox.
    var fillsArt = false

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
            if tiles.showsTitles && tiles.art != .logo && tiles.art != .logoCard {
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
            logoURL = tiles.art == .logo || tiles.art == .logoCard ? game.logoURL : nil
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
            GameCoverArtView(url: game.titleScreenURL ?? game.coverArtURL, title: game.title, showBackground: false, fills: fillsArt)
        case .fanart:
            GameCoverArtView(url: CabinetArt.url(for: game, CabinetTheme.Backdrop.Source.fanart), title: game.title,
                             showBackground: false, fills: fillsArt)
        case .logo:
            if fillsArt {
                // A wide card: the logo over the game's darkened art, so
                // it's a card like the others rather than a bare logo.
                ZStack {
                    GameCoverArtView(url: CabinetArt.url(for: game, CabinetTheme.Backdrop.Source.fanart), title: game.title,
                                     showBackground: false, fills: true)
                        .blur(radius: 6)
                        .overlay(Color.black.opacity(0.55))
                    cardLogo(theme)
                }
            } else {
                logo(theme)
            }
        case .logoCard:
            ZStack {
                theme.palette.surface.color
                cardLogo(theme)
            }
        }
    }

    /// A logo on a card: room around it, and a shadow to lift it off
    /// whatever's behind.
    private func cardLogo(_ theme: CabinetTheme) -> some View {
        logo(theme, onCard: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .shadow(color: .black.opacity(0.7), radius: 8, y: 3)
    }

    @ViewBuilder
    private func logo(_ theme: CabinetTheme, onCard: Bool = false) -> some View {
        if let logoURL {
            GameCoverArtView(url: logoURL, title: game.title, showBackground: false)
        } else {
            // No logo: the title, set like one.
            Text(theme.cased(game.title))
                .font(theme.font(size: theme.typography.titleSize * 0.9, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .foregroundStyle(isFocused || onCard ? theme.palette.text.color : theme.palette.secondaryText.color)
                .shadow(color: .black.opacity(0.6), radius: 3)
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
    /// A logo sits centered, even in a leading column, unless it's to
    /// follow `alignment`.
    var centersLogo = true
    /// A fixed box for the logo, so every game's sits the same size
    /// whatever its shape: the hero's, as big as a card.
    var logoBox: CGSize?

    private var logoAlignment: Alignment {
        centersLogo ? .center : Alignment(horizontal: alignment, vertical: .center)
    }

    @Environment(\.cabinetTheme) private var installed
    @State private var logoURL: URL?

    var body: some View {
        let theme = installed.theme
        Group {
            if theme.details.showsLogo, let logoURL {
                GameCoverArtView(url: logoURL, title: game.title, showBackground: false,
                                 alignment: logoBox == nil ? logoAlignment : .bottomLeading)
                    .frame(maxWidth: logoBox?.width ?? (isLarge ? 500 : 420),
                           maxHeight: logoBox?.height ?? theme.typography.titleSize * (isLarge ? 3.4 : 2.4))
                    .frame(width: logoBox?.width, height: logoBox?.height)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: logoAlignment)
            } else {
                Text(theme.cased(game.title))
                    .font(theme.titleFont)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
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
    /// The game page's: developer, publisher, play time, last played.
    var showsMoreFacts = false
    /// Side by side, when there's the width.
    var factColumns = 1
    /// The facts on one line rather than labeled rows; centered, always.
    var inlineFacts = false

    /// A logo centered even in a leading column; the hero keeps it left.
    var centersLogo = true

    private var factsInline: Bool { inlineFacts || alignment == .center }

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(\.cabinetTheme) private var installed

    var body: some View {
        if let game {
            let theme = installed.theme
            let textAlignment: TextAlignment = alignment == .center ? .center : .leading
            VStack(alignment: alignment, spacing: factsInline ? 10 : 16) {
                if showsTitle {
                    CabinetGameTitle(game: game, alignment: alignment, centersLogo: centersLogo)
                }

                if theme.details.showsMetadata {
                    if factsInline {
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

    /// In `factColumns` columns, filled top to bottom then across.
    private func factRows(for game: Game, theme: CabinetTheme) -> some View {
        let facts = facts(for: game)
        let columns = max(1, factColumns)
        let rows = (facts.count + columns - 1) / columns
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        if let fact = facts[safe: column * rows + row] {
                            factCells(fact, gap: column > 0 ? 28 : 0, theme: theme)
                        }
                    }
                }
            }
        }
        .font(theme.bodyFont())
    }

    /// The icon, label and value, as three grid cells; `gap` goes before
    /// the icon, between columns.
    @ViewBuilder
    private func factCells(_ fact: Fact, gap: CGFloat, theme: CabinetTheme) -> some View {
        Image(systemName: fact.symbol)
            .foregroundStyle(theme.palette.accent.color)
            .frame(width: theme.typography.bodySize * 1.3)
            .padding(.leading, gap)
        Text(fact.label)
            .foregroundStyle(theme.palette.secondaryText.color)
        Group {
            if let stars = fact.stars {
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= stars ? "star.fill" : "star")
                            .foregroundStyle(star <= stars ? theme.palette.favorite.color : theme.palette.secondaryText.color)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(fact.value))
            } else {
                Text(verbatim: fact.value)
                    .foregroundStyle(theme.palette.text.color)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Fact {
        let symbol: String
        let label: String
        let value: String
        /// A rating, out of five, drawn as stars beside the label.
        var stars: Int?
    }

    private func facts(for game: Game) -> [Fact] {
        var facts: [Fact] = []
        if let system = game.system?.displayName {
            facts.append(Fact(symbol: "gamecontroller", label: String(localized: "System"), value: system))
        }
        // Release dates are stored at midnight UTC.
        if let released = game.releaseDate, showsMoreFacts {
            facts.append(Fact(symbol: "calendar", label: String(localized: "Released"),
                              value: released.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))))
        } else if let year = game.releaseYear {
            facts.append(Fact(symbol: "calendar", label: String(localized: "Year"), value: String(year)))
        }
        if let genre = game.genre {
            facts.append(Fact(symbol: "tag", label: String(localized: "Genre"), value: genre))
        }
        // `players` is free text from scrapers ("1", "1-2", "1-4"), so it
        // can't drive a plural — label it instead.
        if let players = game.players {
            facts.append(Fact(symbol: "person.2", label: String(localized: "Players"),
                              value: factsInline ? String(localized: "Players: \(players)") : players))
        }
        if let rating = game.rating, rating > 0 {
            let stars = Int((rating * 5).rounded())
            facts.append(Fact(symbol: "star", label: String(localized: "Rating"),
                              value: String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars),
                              stars: stars))
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
            let value = if factsInline {
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

extension Game {
    /// Gamelists store release dates as UTC midnight: read in the local
    /// time zone, west of Greenwich, January 1st falls in the year before.
    var releaseYear: Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return releaseDate.map { calendar.component(.year, from: $0) }
    }
}
