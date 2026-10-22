import ImageIO
import PDFKit
import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// A game's page in Cabinet Mode, between choosing it and playing it: its
/// art, video, facts and description, and Play, Favorite, Collections and
/// Manual. Left and right pick an action, up and down scroll the
/// description, B goes back to the games.
struct CabinetGamePage: View {
    let game: Game
    let event: CabinetEvent?
    let onPlay: (Game) -> Void
    let onClose: () -> Void

    @Environment(\.cabinetTheme) private var installed
    @Environment(GamepadInputMonitor.self) private var gamepad
    @Environment(LaunchCoordinator.self) private var launchCoordinator
    @AppStorage(GameHeaderMedia.previewsKey) private var playsPreviews = true
    @AppStorage("videoPreviewsMuted") private var isMuted = true

    @State private var focusedAction = Action.play
    @State private var videoURL: URL?
    @State private var manualURL: URL?
    /// Looked up once: the 3D box lives by file alone.
    @State private var box3DURL: URL?
    /// The box picture's width over its height: SNES boxes lie wide,
    /// most others stand tall.
    @State private var boxAspect: CGFloat?
    @State private var descriptionScroll = ScrollPosition(y: 0)
    @State private var descriptionOffset: CGFloat = 0
    /// What's open over the page.
    @State private var overlay: Overlay?
    @State private var overlayEvent: CabinetEvent?
    @State private var overlaySequence = 0

    enum Action: CaseIterable {
        case play, favorite, collections, manual
    }

    enum Overlay {
        case collections, manual(URL)
    }

    private var actions: [Action] {
        Action.allCases.filter { $0 != .manual || manualURL != nil }
    }

    var body: some View {
        let theme = installed.theme
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            // What the game is on one side: box, logo and facts, the
            // description, the actions. Its video, centered, on the other.
            // Details Side says which side the box and facts take.
            HStack(spacing: 64) {
                if theme.details.side == .leading { info(theme) }
                video(theme)
                if theme.details.side == .trailing { info(theme) }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 56)

            switch overlay {
            case .collections:
                CabinetCollectionPicker(game: game, event: overlayEvent, onClose: { overlay = nil })
                    .transition(.opacity)
            case .manual(let url):
                CabinetManualView(url: url, event: overlayEvent, onClose: { overlay = nil })
                    .transition(.opacity)
            case nil:
                EmptyView()
            }
        }
        .animation(.snappy(duration: 0.2), value: overlay == nil)
        .onChange(of: event) { _, newEvent in
            if let newEvent { handle(newEvent.command) }
        }
        .task(id: game.persistentModelID) {
            manualURL = game.manualURL
            box3DURL = game.box3DURL
            boxAspect = Self.aspectRatio(of: box3DURL ?? game.coverArtURL)
            videoURL = nil
            guard playsPreviews, let url = game.previewVideoURL, GameHeaderMedia.canPlay(url) else { return }
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { videoURL = url }
        }
    }

    // MARK: Pieces

    private func info(_ theme: CabinetTheme) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .top, spacing: 32) {
                box(theme)
                VStack(alignment: .leading, spacing: 16) {
                    CabinetGameTitle(game: game, alignment: .leading, centersLogo: false)
                    CabinetGameInfo(game: game, alignment: .leading, showsDescription: false, showsTitle: false,
                                    showsMoreFacts: true)
                }
            }
            description(theme)
            actionRow(theme)
        }
        // Two fifths of the page: the description reads as a block
        // rather than one long line, and the video gets the rest.
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// The 3D box when there is one, else the 2D one, at its own shape
    /// within a square: as tall as the facts when it stands, as wide
    /// when it lies.
    private func box(_ theme: CabinetTheme) -> some View {
        GameCoverArtView(url: box3DURL ?? game.coverArtURL, title: game.title, showBackground: false)
            .aspectRatio(boxAspect ?? 0.75, contentMode: .fit)
            .frame(maxWidth: 300, maxHeight: 300)
            .frame(width: 300, alignment: .topLeading)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    /// Read from the file's header, without decoding the picture.
    private static func aspectRatio(of url: URL?) -> CGFloat? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, height > 0 else { return nil }
        return width / height
    }

    /// The whole description, scrolled with up and down.
    @ViewBuilder
    private func description(_ theme: CabinetTheme) -> some View {
        if let description = game.gameDescription, !description.isEmpty {
            ScrollView(.vertical) {
                Text(description)
                    .font(theme.bodyFont())
                    .lineSpacing(4)
                    .foregroundStyle(theme.palette.secondaryText.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollPosition($descriptionScroll)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in descriptionOffset = y }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)
        }
    }

    /// The screenshot, the video fading in over it, kept to a modest size
    /// and centered in its column.
    @ViewBuilder
    private func video(_ theme: CabinetTheme) -> some View {
        if videoURL != nil || game.titleScreenURL != nil {
            ZStack {
                GameCoverArtView(url: game.titleScreenURL, title: game.title, showBackground: false)
                if let videoURL {
                    VideoPreviewView(url: videoURL, isMuted: isMuted)
                        .transition(.opacity)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: theme.tiles.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            .frame(maxWidth: 1280, maxHeight: 960)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func actionRow(_ theme: CabinetTheme) -> some View {
        HStack(spacing: 14) {
            ForEach(actions, id: \.self) { action in
                let isFocused = action == focusedAction
                Label(title(of: action), systemImage: symbol(of: action))
                    .font(theme.largeFont(isFocused ? .bold : .medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .foregroundStyle(isFocused ? theme.palette.background.color : theme.palette.text.color)
                    .background(isFocused ? theme.palette.accent.color : theme.palette.surface.color, in: Capsule())
                    .scaleEffect(isFocused ? 1.06 : 1)
                    .animation(.snappy(duration: 0.15), value: isFocused)
                    .onTapGesture {
                        focusedAction = action
                        perform(action)
                    }
            }
        }
    }

    private func title(of action: Action) -> String {
        switch action {
        case .play: launchCoordinator.state == .running(gameID: game.persistentModelID) ? String(localized: "Playing") : String(localized: "Play")
        case .favorite: game.favorite ? String(localized: "Favorite") : String(localized: "Add to Favorites")
        case .collections: String(localized: "Collections")
        case .manual: String(localized: "Manual")
        }
    }

    private func symbol(of action: Action) -> String {
        switch action {
        case .play: "play.fill"
        case .favorite: game.favorite ? "star.fill" : "star"
        case .collections: "rectangle.stack"
        case .manual: "book"
        }
    }

    // MARK: Input

    private func handle(_ command: CabinetEvent.Command) {
        if overlay != nil {
            overlaySequence += 1
            overlayEvent = CabinetEvent(command: command, sequence: overlaySequence)
            return
        }
        let actions = actions
        let index = actions.firstIndex(of: focusedAction) ?? 0
        switch command {
        case .move(.left): focusedAction = actions[max(0, index - 1)]
        case .move(.right): focusedAction = actions[min(actions.count - 1, index + 1)]
        case .move(.up): scrollDescription(by: -160)
        case .move(.down): scrollDescription(by: 160)
        case .activate: perform(focusedAction)
        case .toggleFavorite: perform(.favorite)
        case .back, .details: onClose()
        default: break
        }
    }

    private func scrollDescription(by amount: CGFloat) {
        withAnimation(.snappy(duration: 0.2)) { descriptionScroll.scrollTo(y: max(0, descriptionOffset + amount)) }
    }

    private func perform(_ action: Action) {
        switch action {
        case .play: onPlay(game)
        case .favorite:
            game.favorite.toggle()
            try? game.modelContext?.save()
        case .collections: overlay = .collections
        case .manual: if let manualURL { overlay = .manual(manualURL) }
        }
    }
}

/// Which collections a game is in, ticked with the pad.
private struct CabinetCollectionPicker: View {
    let game: Game
    let event: CabinetEvent?
    let onClose: () -> Void

    @Query(sort: \GameCollection.name) private var collections: [GameCollection]
    @Environment(\.cabinetTheme) private var installed
    @State private var focused = 0

    var body: some View {
        let theme = installed.theme
        VStack(alignment: .leading, spacing: 6) {
            Text("Collections")
                .font(theme.font(size: theme.typography.titleSize * 0.8, weight: .bold))
                .padding(.bottom, 10)
            if collections.isEmpty {
                Text("No collections yet: switch some on in Settings › Collections.")
                    .font(theme.bodyFont())
                    .foregroundStyle(theme.palette.secondaryText.color)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                            let isFocused = index == focused
                            HStack {
                                Image(systemName: collection.contains(game) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(collection.contains(game) ? theme.palette.accent.color : theme.palette.secondaryText.color)
                                Text(collection.name)
                                Spacer()
                            }
                            .font(theme.largeFont(isFocused ? .semibold : .regular))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(isFocused ? theme.palette.surface.color : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if isFocused { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.palette.accent.color, lineWidth: 2) }
                            }
                            .id(index)
                            .onTapGesture { focused = index; toggle(collection) }
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: focused) { _, index in withAnimation { proxy.scrollTo(index) } }
            }
        }
        .padding(28)
        .frame(width: 560)
        .frame(maxHeight: 620)
        .background(theme.palette.background.color.opacity(0.95), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 40)
        .onChange(of: event) { _, newEvent in
            guard let command = newEvent?.command else { return }
            switch command {
            case .move(.up): focused = max(0, focused - 1)
            case .move(.down): focused = min(max(0, collections.count - 1), focused + 1)
            case .activate: if let collection = collections[safe: focused] { toggle(collection) }
            case .back: onClose()
            default: break
            }
        }
    }

    private func toggle(_ collection: GameCollection) {
        let isMember = !collection.contains(game)
        collection.setContains(game, isMember)
        if isMember {
            collection.excludedGameKeys.removeAll { $0 == game.collectionKey }
        } else if collection.addsMatchingGames, !collection.excludedGameKeys.contains(game.collectionKey) {
            // So its search doesn't add it back after the next scan.
            collection.excludedGameKeys.append(game.collectionKey)
        }
        try? game.modelContext?.save()
    }
}

/// A game's manual, a page at a time: left and right turn pages, B closes.
private struct CabinetManualView: View {
    let url: URL
    let event: CabinetEvent?
    let onClose: () -> Void

    @Environment(\.cabinetTheme) private var installed
    @State private var document: PDFDocument?
    @State private var page = 0

    var body: some View {
        let theme = installed.theme
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.85).ignoresSafeArea()
            if let document {
                PDFPageView(document: document, pageIndex: page)
                    .padding(.horizontal, 80)
                    .padding(.top, 40)
                    .padding(.bottom, 90)
                Text("Page \(page + 1) of \(document.pageCount)")
                    .font(theme.bodyFont(.medium))
                    .foregroundStyle(theme.palette.secondaryText.color)
                    .padding(.bottom, 36)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) { document = PDFDocument(url: url) }
        .onChange(of: event) { _, newEvent in
            guard let command = newEvent?.command, let count = document?.pageCount else { return }
            switch command {
            case .move(.left), .move(.up), .previousSection: page = max(0, page - 1)
            case .move(.right), .move(.down), .nextSection: page = min(count - 1, page + 1)
            case .back: onClose()
            default: break
            }
        }
    }
}

/// One page of a PDF, fitted.
private struct PDFPageView: NSViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.autoScales = true
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if let page = document.page(at: pageIndex), view.currentPage != page { view.go(to: page) }
    }
}
