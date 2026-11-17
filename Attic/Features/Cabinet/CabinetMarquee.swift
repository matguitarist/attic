import AppKit
import SwiftUI
import AtticModels
import AtticPersistence

/// The screen a real cabinet has above its main one, kept by name like
/// Cabinet Mode's own (`CabinetDisplay`). Empty for none.
enum CabinetMarqueeDisplay {
    static let key = "cabinetMarqueeDisplay"

    static var chosenName: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The chosen screen, while it's connected and isn't the one Cabinet
    /// Mode is on.
    @MainActor static var screen: NSScreen? {
        let name = chosenName
        guard !name.isEmpty, let screen = NSScreen.screens.first(where: { $0.localizedName == name }) else { return nil }
        if let cabinet = CabinetWindows.cabinet?.screen, cabinet == screen { return nil }
        return screen
    }

    /// "None", then every connected screen, then the chosen one when it
    /// isn't connected now, so choosing doesn't lose it.
    static var options: [String] {
        let names = NSScreen.screens.map(\.localizedName)
        let chosen = chosenName
        return [""] + names + (chosen.isEmpty || names.contains(chosen) ? [] : [chosen])
    }

    static func title(of option: String) -> String {
        option.isEmpty ? String(localized: "None") : option
    }
}

/// What the marquee screen shows: Cabinet Mode keeps it up to date as
/// focus moves.
@MainActor @Observable
final class CabinetMarqueeModel {
    var theme: CabinetTheme = .showcase
    var gameTitle: String?
    var marqueeURL: URL?
    var logoURL: URL?
    var sectionTitle = ""
    var sectionLogo: Image?

    var content: CabinetTheme.Marquee.Content {
        .resolve(hasGame: gameTitle != nil, hasMarquee: marqueeURL != nil, hasLogo: logoURL != nil, sectionHasLogo: sectionLogo != nil)
    }

    /// The focused game, or nil on the systems.
    func show(_ game: Game?, section: CabinetSection?) {
        gameTitle = game?.title
        // Looked up here, once per focus: they live by file alone.
        marqueeURL = game?.marqueeURL
        logoURL = game?.logoURL
        sectionTitle = section?.title ?? ""
        sectionLogo = section?.logo
    }
}

/// The marquee's window while Cabinet Mode is open: full screen on the
/// chosen display, closed while that display is away and back when it
/// returns, so plugging and unplugging never stops Cabinet Mode.
@MainActor
final class CabinetMarqueeWindow {
    static let shared = CabinetMarqueeWindow()

    let model = CabinetMarqueeModel()
    private var window: NSWindow?
    private var screensObserver: NSObjectProtocol?
    private var isActive = false

    func start() {
        isActive = true
        if screensObserver == nil {
            screensObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { CabinetMarqueeWindow.shared.refresh() }
            }
        }
        refresh()
    }

    func stop() {
        isActive = false
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        screensObserver = nil
        close()
    }

    /// Opens, moves or closes the window for the display chosen now.
    func refresh() {
        guard isActive, let screen = CabinetMarqueeDisplay.screen else {
            close()
            return
        }
        let window = self.window ?? makeWindow()
        if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: CabinetMarqueeView(model: model))
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        // Over the menu bar of its screen, and staying there while a game
        // plays on the main one.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        self.window = window
        return window
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}

/// The marquee screen: the focused game's marquee, else its logo, else its
/// title; on the systems, the system's logo. Fit and background from the
/// theme.
struct CabinetMarqueeView: View {
    let model: CabinetMarqueeModel

    var body: some View {
        let theme = model.theme
        let content = model.content
        ZStack {
            theme.marquee.background.color
            picture(content, theme: theme)
                .id(identity(content))
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: identity(content))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func picture(_ content: CabinetTheme.Marquee.Content, theme: CabinetTheme) -> some View {
        switch content {
        case .gameMarquee:
            GameCoverArtView(url: model.marqueeURL, title: model.gameTitle ?? "", showBackground: false,
                             fills: theme.marquee.fit == .fill, cornerRadius: 0)
        case .gameLogo:
            GameCoverArtView(url: model.logoURL, title: model.gameTitle ?? "", showBackground: false)
                .padding(.vertical, 24)
                .padding(.horizontal, 48)
        case .gameTitle:
            title(model.gameTitle ?? "", theme: theme)
        case .sectionLogo:
            model.sectionLogo?
                .resizable()
                .scaledToFit()
                .padding(.vertical, 28)
                .padding(.horizontal, 56)
        case .sectionTitle:
            title(model.sectionTitle, theme: theme)
        }
    }

    private func title(_ text: String, theme: CabinetTheme) -> some View {
        Text(verbatim: theme.cased(text))
            .font(theme.font(size: 200, weight: .heavy))
            .minimumScaleFactor(0.1)
            .lineLimit(1)
            .foregroundStyle(theme.palette.text.color)
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
    }

    /// Changes when what's shown does, for the cross-fade.
    private func identity(_ content: CabinetTheme.Marquee.Content) -> String {
        switch content {
        case .gameMarquee: model.marqueeURL?.path ?? ""
        case .gameLogo: model.logoURL?.path ?? ""
        case .gameTitle: "title|" + (model.gameTitle ?? "")
        case .sectionLogo, .sectionTitle: "section|" + model.sectionTitle
        }
    }
}
