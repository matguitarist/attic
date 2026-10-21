import SwiftUI
import AtticModels
import AtticPersistence

/// One game in a layout: its cover, screenshot or logo per the theme,
/// grown and lit when focused.
struct CabinetTile: View {
    let game: Game
    let isFocused: Bool

    @Environment(\.cabinetTheme) private var installed
    /// Looked up once: the logo lives by file alone.
    @State private var logoURL: URL?

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
                    if game.favorite {
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
        .task(id: game.persistentModelID) {
            if tiles.art == .logo { logoURL = game.logoURL }
        }
    }

    @ViewBuilder
    private func art(_ theme: CabinetTheme) -> some View {
        switch theme.tiles.art {
        case .cover:
            GameCoverArtView(url: game.coverArtURL, title: game.title, showBackground: false)
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

/// The focused game's title (or logo), facts, state and description, as
/// much as the theme shows.
struct CabinetGameInfo: View {
    let game: Game?
    let alignment: HorizontalAlignment

    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @Environment(\.cabinetTheme) private var installed
    @State private var logoURL: URL?

    var body: some View {
        if let game {
            let theme = installed.theme
            let textAlignment: TextAlignment = alignment == .center ? .center : .leading
            VStack(alignment: alignment, spacing: 10) {
                if theme.details.showsLogo, let logoURL {
                    GameCoverArtView(url: logoURL, title: game.title, showBackground: false)
                        .frame(maxWidth: 420, maxHeight: theme.typography.titleSize * 2.4)
                        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
                } else {
                    Text(theme.cased(game.title))
                        .font(theme.titleFont)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(textAlignment)
                }

                if theme.details.showsMetadata {
                    Text(metadata(for: game))
                        .font(theme.bodyFont())
                        .foregroundStyle(theme.palette.secondaryText.color)
                        .multilineTextAlignment(textAlignment)
                }

                if launchCoordinator.state == .running(gameID: game.persistentModelID) {
                    Label("Playing", systemImage: "gamecontroller.fill")
                        .font(theme.bodyFont(.semibold))
                        .foregroundStyle(.green)
                } else if case .failed(let message) = launchCoordinator.state {
                    Text(message)
                        .font(theme.bodyFont())
                        .foregroundStyle(.red)
                } else if theme.details.showsDescription, let description = game.gameDescription {
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
            .task(id: game.persistentModelID) {
                logoURL = theme.details.showsLogo ? game.logoURL : nil
            }
        }
    }

    private func metadata(for game: Game) -> String {
        var parts: [String] = []
        if let system = game.system?.displayName { parts.append(system) }
        if let year = game.releaseDate.map({ Calendar.current.component(.year, from: $0) }) { parts.append(String(year)) }
        if let genre = game.genre { parts.append(genre) }
        // `players` is free text from scrapers ("1", "1-2", "1-4"), so it
        // can't drive a plural — label it instead.
        if let players = game.players { parts.append(String(localized: "Players: \(players)")) }
        if game.playCount > 0 { parts.append(String(localized: "Played \(game.playCount)×")) }
        return parts.joined(separator: "  ·  ")
    }
}
