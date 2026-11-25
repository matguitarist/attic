import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import PictureKitUI

/// Cabinet Mode's screensaver, as arcade cabinets do it: after a while with
/// no input, random games show their video (or, without one, their art,
/// slowly zooming), with their name. A plays the game on screen; any other
/// button goes back to where you were. Colors and type come from the theme.
struct CabinetAttractView: View {
    let event: CabinetEvent?
    let onPlay: (Game) -> Void
    let onClose: () -> Void
    /// The first game shown (the snapshot's); else one is picked.
    var first: Game? = nil

    @Environment(\.cabinetTheme) private var installed
    @Environment(\.modelContext) private var modelContext
    @AppStorage("videoPreviewsMuted") private var isMuted = true
    @State private var game: Game?
    @State private var videoURL: URL?
    @State private var image: CGImage?
    @State private var zoomed = false
    /// Games shown recently, so the same few don't come back.
    @State private var recent: [PersistentIdentifier] = []

    /// How long a game stays: its video's first half minute, or a picture's
    /// slow zoom.
    private static let videoSeconds = 30.0
    private static let pictureSeconds = 9.0

    /// The setting: minutes without input before it starts; 0 is never.
    static let minutesKey = "cabinetAttractMinutes"
    static let defaultMinutes = 5
    static let minuteChoices = [0, 2, 5, 10, 20]

    var body: some View {
        let theme = installed.theme
        ZStack(alignment: .bottomLeading) {
            // The media hang off a flexible color so their fill never
            // sizes the layout (see CabinetBackdrop).
            Color.black
                .overlay {
                    if let videoURL {
                        VideoPreviewView(url: videoURL, isMuted: isMuted)
                            .transition(.opacity)
                            .id(videoURL)
                    } else if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(zoomed ? 1.12 : 1)
                            .animation(.linear(duration: Self.pictureSeconds), value: zoomed)
                            .transition(.opacity)
                            .id(game?.persistentModelID)
                    }
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            if let game {
                VStack(alignment: .leading, spacing: 10) {
                    Text(game.title)
                        .font(theme.font(size: theme.typography.titleSize * 1.2, weight: .bold))
                    if let system = game.system?.displayName {
                        Text(verbatim: system)
                            .font(theme.largeFont(.medium))
                            .foregroundStyle(theme.palette.secondaryText.color)
                    }
                    Text("Press A to play, any other button to go back")
                        .font(theme.bodyFont())
                        .foregroundStyle(theme.palette.secondaryText.color)
                        .padding(.top, 6)
                }
                .foregroundStyle(theme.palette.text.color)
                .padding(64)
                .id(game.persistentModelID)
                .transition(.opacity)
            }
        }
        .clipped()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: game?.persistentModelID)
        .task(id: game?.persistentModelID) {
            if game == nil {
                game = first ?? pick()
                return
            }
            await show()
        }
        .onChange(of: event) { _, newEvent in
            guard let newEvent else { return }
            if newEvent.command == .activate, let game { onPlay(game) } else { onClose() }
        }
    }

    /// Loads the game's video or picture, waits, then moves to another.
    private func show() async {
        guard let game else { return }
        zoomed = false
        let video = game.previewVideoURL.flatMap { GameHeaderMedia.canPlay($0) ? $0 : nil }
        videoURL = video
        image = nil
        if video == nil, let art = game.fanartURL ?? game.titleScreenURL ?? game.coverArtURL {
            image = await PictureCache.shared.image(.file(art), maxPixels: 1920)
            zoomed = true
        }
        try? await Task.sleep(for: .seconds(video == nil ? Self.pictureSeconds : Self.videoSeconds))
        guard !Task.isCancelled else { return }
        if let next = pick() { self.game = next }
    }

    /// A random game with a video or a picture, preferring videos, not one
    /// of the last few.
    private func pick() -> Game? {
        var descriptor = FetchDescriptor<Game>()
        guard let count = try? modelContext.fetchCount(descriptor), count > 0 else { return nil }
        var fallback: Game?
        for _ in 0..<24 {
            descriptor.fetchOffset = Int.random(in: 0..<count)
            descriptor.fetchLimit = 1
            guard let candidate = try? modelContext.fetch(descriptor).first,
                  count < 8 || !recent.contains(candidate.persistentModelID) else { continue }
            if candidate.previewVideoURL.map(GameHeaderMedia.canPlay) == true {
                remember(candidate)
                return candidate
            }
            if fallback == nil, (candidate.fanartURL ?? candidate.titleScreenURL ?? candidate.coverArtURL) != nil {
                fallback = candidate
            }
        }
        if let fallback { remember(fallback) }
        return fallback
    }

    private func remember(_ game: Game) {
        recent.append(game.persistentModelID)
        if recent.count > 8 { recent.removeFirst() }
    }
}
