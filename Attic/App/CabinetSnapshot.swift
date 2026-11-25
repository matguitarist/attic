import AppKit
import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticLibraryScanning
import AtticEmulation
import PictureKitUI

/// Pictures of Cabinet Mode for checking a change without a library or a
/// person at the screen: `ATTIC_SNAPSHOT=<folder>` (see tools/snap.sh)
/// seeds an in-memory library with drawn art in a scratch ROMs folder,
/// draws each built-in theme's layout in an offscreen window, writes one
/// PNG per theme and Game Art, and quits. The person's library, settings
/// and folders are never opened.
///
/// `ATTIC_SNAPSHOT_THEMES` (theme ids) and `ATTIC_SNAPSHOT_ARTS` (Game Art
/// values, or `own` for the theme's own) narrow it, comma-separated.
@MainActor
enum CabinetSnapshot {
    static let size = CGSize(width: 1280, height: 800)

    static var folder: URL? {
        ProcessInfo.processInfo.environment["ATTIC_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Writes the pictures, then quits the app.
    static func run(into folder: URL) -> Never {
        let environment = ProcessInfo.processInfo.environment
        let themeIDs = list(environment["ATTIC_SNAPSHOT_THEMES"])
        let arts = list(environment["ATTIC_SNAPSHOT_ARTS"]) ?? ["own", "medium", "mix"]
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if themeIDs == nil || themeIDs?.contains("picture") == true {
                try checkIncomingPicture(into: folder)
            }
            let seed = try Seed()
            for theme in CabinetTheme.builtIns where themeIDs?.contains(theme.id) ?? true {
                for art in arts {
                    var shown = theme
                    if art != "own" {
                        guard let value = CabinetTheme.Tiles.Art(rawValue: art) else { continue }
                        shown.tiles.art = value
                    }
                    let file = folder.appending(path: "\(theme.id)-\(art).png")
                    try capture(shelf(seed, theme: shown), to: file)
                    print(file.path)
                }
            }
            if themeIDs == nil || themeIDs?.contains("editor") == true {
                // The whole form at once, every section in sight.
                let form = folder.appending(path: "editor-form.png")
                try capture(EditorForm(), to: form, size: CGSize(width: 420, height: 3400))
                print(form.path)
                for page in [ThemePreviewPage.games, .systems, .marquee] {
                    let file = folder.appending(path: "editor-\(page.rawValue).png")
                    try capture(EditorStage(page: page).modelContainer(seed.container).environment(seed.launchCoordinator),
                                to: file, size: CGSize(width: 1360, height: 820))
                    print(file.path)
                }
            }
            if themeIDs == nil || themeIDs?.contains("page") == true {
                try gamePage(seed, into: folder)
            }
            if themeIDs == nil || themeIDs?.contains("marquee") == true {
                try marquees(seed, into: folder)
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// The marquee screen in each of its states, and with a theme that
    /// fills it.
    private static func marquees(_ seed: Seed, into folder: URL) throws {
        let byTitle = Dictionary(uniqueKeysWithValues: seed.games.map { ($0.title, $0) })
        let systemLogo = NSImage(data: Art.logo("SUPER NES", color: .systemPurple)).map { Image(nsImage: $0) }
        var filled = CabinetTheme.arcade
        filled.marquee = CabinetTheme.Marquee(fit: .fill, background: ThemeColor(hex: "#1B2838")!)
        let shots: [(name: String, theme: CabinetTheme, game: Game?, logo: Image?)] = [
            ("marquee-game", .arcade, byTitle["Rocket Zone"], nil),
            ("marquee-game-fill", filled, byTitle["Rocket Zone"], nil),
            ("marquee-logo", .arcade, byTitle["Comet Racer"], nil),
            ("marquee-system", .arcade, nil, systemLogo),
            ("marquee-section-title", .classic, nil, nil)
        ]
        for shot in shots {
            let model = CabinetMarqueeModel()
            model.theme = shot.theme
            model.show(shot.game, section: CabinetSection(selection: .system("snes"), title: "Super Nintendo", logo: shot.logo))
            let file = folder.appending(path: "\(shot.name).png")
            try capture(CabinetMarqueeView(model: model).modelContainer(seed.container), to: file, size: CGSize(width: 1280, height: 400))
            print(file.path)
        }
    }

    /// A game's page with save states, and their picker, with the game's
    /// pictures standing in for the states' screenshots.
    private static func gamePage(_ seed: Seed, into folder: URL) throws {
        let game = seed.games[1]
        let pictures = seed.games.compactMap(\.coverArtURL)
        let states = pictures.prefix(3).enumerated().map { index, url in
            SaveState(slot: index + 1, url: url, thumbnail: url, date: Date.now.addingTimeInterval(Double(-3600 * (index * 20 + 2))))
        }
        let theme = CabinetTheme.builtIns[0]
        let page = folder.appending(path: "page-savestates.png")
        try capture(CabinetGamePage(game: game, event: nil, onPlay: { _ in }, onPlayState: { _, _ in }, onClose: {}, saveStates: states)
            .background(theme.palette.background.color)
            .environment(\.cabinetTheme, CabinetThemeStore.Installed(theme: theme))
            .environment(seed.launchCoordinator)
            .environment(seed.gamepad)
            .modelContainer(seed.container), to: page)
        print(page.path)
        let picker = folder.appending(path: "page-savestates-picker.png")
        try capture(ZStack {
            theme.palette.background.color
            CabinetSaveStatePicker(states: states, event: nil, onPick: { _ in }, onClose: {})
        }
        .environment(\.cabinetTheme, CabinetThemeStore.Installed(theme: theme)), to: picker)
        print(picker.path)
        let attract = folder.appending(path: "attract.png")
        try capture(CabinetAttractView(event: nil, onPlay: { _ in }, onClose: {}, first: seed.games[2])
            .environment(\.cabinetTheme, CabinetThemeStore.Installed(theme: theme))
            .modelContainer(seed.container), to: attract)
        print(attract.path)
        let pin = folder.appending(path: "kid-pin.png")
        try capture(ZStack {
            Color.gray
            CabinetPINView(event: nil, onSuccess: {}, onCancel: {})
        }
        .environment(\.cabinetTheme, CabinetThemeStore.Installed(theme: theme)), to: pin)
        print(pin.path)
    }

    private static func list(_ value: String?) -> [String]? {
        value.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    /// The theme's layout over its background, the second game focused so
    /// there are games on both sides.
    private static func shelf(_ seed: Seed, theme: CabinetTheme) -> some View {
        let content = CabinetShelfContent(games: seed.games, focusedID: seed.games[1].persistentModelID,
                                          onFocus: { _ in }, onPlay: { _ in })
        return ZStack {
            theme.palette.background.color
            CabinetLayoutSwitch(shelf: content, layout: theme.layout)
                .padding(.vertical, 40)
        }
        .environment(\.cabinetTheme, CabinetThemeStore.Installed(theme: theme))
        .environment(seed.launchCoordinator)
        .modelContainer(seed.container)
    }

    /// Draws `view` offscreen, waits for its pictures and animations, and
    /// writes it as a PNG.
    static func capture(_ view: some View, to file: URL, size: CGSize = size) throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .darkAqua)
        window.orderFrontRegardless()
        // Pictures load off the main thread; the Unboxed disc comes out
        // after a moment.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.2))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw SnapshotError.capture }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.capture }
        try data.write(to: file)
        window.orderOut(nil)
    }

    enum SnapshotError: Error {
        case capture
        case picture(String)
    }

    /// Checks the way every scraped or picked cover comes in: a heavy PNG
    /// is stored as HEIC, smaller and the same size, and the cover view
    /// shows it. Writes `picture-check.png`.
    private static func checkIncomingPicture(into folder: URL) throws {
        let roms = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Attic-snapshot-picture/ROMs/snes", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: roms.deletingLastPathComponent().deletingLastPathComponent())
        // Noise over a gradient, like a scanned box: what PNG is worst at.
        let (width, height) = (900, 1200)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = UInt8.random(in: 0...255)
            pixels[index + 1] = UInt8(index / 4 % width * 255 / width)
            pixels[index + 2] = UInt8(index / 4 / width * 255 / height)
        }
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage(), let png = Pictures.encode(image, as: .png) else { throw SnapshotError.picture("no PNG drawn") }
        let stored = try MediaFolder.store(png, fileExtension: "png", forSystemFolder: roms, romRelativePath: "Picture Check.sfc", kind: .covers)
        let bytes = MediaFolder.fileSize(stored)
        guard stored.pathExtension == "heic", bytes < png.count,
              let info = Pictures.info(at: stored), info.width == width, info.height == height else {
            throw SnapshotError.picture("cover stored as \(stored.lastPathComponent), \(bytes) bytes from \(png.count)")
        }
        let file = folder.appending(path: "picture-check.png")
        let size = CGSize(width: 300, height: 400)
        try capture(GameCoverArtView(url: stored, title: "Picture Check", showBackground: false), to: file, size: size)
        let shown = (1...3).contains { scale in
            PictureCache.shared.cached(.file(stored), maxPixels: Int(size.height) * scale) != nil
        }
        guard shown else { throw SnapshotError.picture("the stored cover wasn't shown") }
        print("Picture check: cover stored as HEIC, \(bytes / 1024) KB from \(png.count / 1024) KB, and shown")
        print(file.path)
    }

    /// A few games in a scratch ROMs folder, each with drawn art: SNES
    /// cartridges (one without a picture of its cartridge), PlayStation
    /// discs, and arcade boards with marquees.
    @MainActor struct Seed {
        let container: ModelContainer
        let games: [Game]
        let launchCoordinator: LaunchCoordinator
        /// For the game page, which reads the pad's buttons.
        let gamepad: GamepadInputMonitor

        init() throws {
            let roms = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Attic-snapshot-roms", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: roms)
            container = try AtticModelContainer.makeInMemory()
            let defaults = UserDefaults(suiteName: "attic.snapshot") ?? .standard
            let emulation = EmulationFolderStore(userDefaults: defaults, romsRoots: [roms])
            let controllerSettings = ControllerSettingsStore(userDefaults: defaults, emulationFolderStore: emulation)
            launchCoordinator = LaunchCoordinator(controllerSettingsStore: controllerSettings)
            gamepad = GamepadInputMonitor(controllerSettingsStore: controllerSettings)

            let entries: [(system: String, file: String, title: String, hue: Double, medium: Bool)] = [
                ("snes", "Comet Racer.sfc", "Comet Racer", 0.02, true),
                ("snes", "Dungeon Bells.sfc", "Dungeon Bells", 0.58, true),
                ("psx", "Glass Harbor.cue", "Glass Harbor", 0.33, true),
                ("snes", "Moss Knight.sfc", "Moss Knight", 0.12, false),
                ("psx", "Night Signal.cue", "Night Signal", 0.75, true),
                ("mame", "rocketz.zip", "Rocket Zone", 0.9, true),
                ("psx", "Tidal Quest.cue", "Tidal Quest", 0.48, true),
                ("mame", "vectorx.zip", "Vector X", 0.2, true)
            ]
            let context = container.mainContext
            var games: [Game] = []
            for entry in entries {
                let systemFolder = roms.appending(path: entry.system, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: systemFolder, withIntermediateDirectories: true)
                let rom = systemFolder.appending(path: entry.file)
                try Data().write(to: rom)
                func store(_ kind: MediaKind, _ data: Data) throws -> URL {
                    try MediaFolder.store(data, fileExtension: "png", forSystemFolder: systemFolder, romRelativePath: entry.file, kind: kind)
                }
                let color = NSColor(hue: entry.hue, saturation: 0.65, brightness: 0.8, alpha: 1)
                let cover = try store(.covers, Art.box(entry.title, color: color, size: CGSize(width: 600, height: 800)))
                _ = try store(.boxes3D, Art.box(entry.title + " 3D", color: color.blended(withFraction: 0.3, of: .black) ?? color,
                                                size: CGSize(width: 640, height: 800), slanted: true))
                let screenshot = try store(.screenshots, Art.box(entry.title, color: color.blended(withFraction: 0.5, of: .darkGray) ?? color,
                                                                 size: CGSize(width: 640, height: 480)))
                _ = try store(.logos, Art.logo(entry.title, color: color))
                if entry.medium {
                    let medium = PhysicalMedium.of(CanonicalSystemID(entry.system))
                    _ = try store(.physicalMedia, medium == .disc ? Art.disc(color: color) : Art.cartridge(entry.title, color: color))
                }
                if entry.system == "mame" {
                    _ = try store(.marquees, Art.box(entry.title.uppercased(), color: color, size: CGSize(width: 1200, height: 300)))
                }
                let game = Game(system: nil, systemCanonicalID: CanonicalSystemID(entry.system), romRelativePath: entry.file,
                                romAbsoluteURL: rom, title: entry.title, description: "A made-up game for checking how Cabinet Mode draws its art.",
                                releaseDate: Date(timeIntervalSince1970: 790_000_000), developer: "Attic", genre: "Action",
                                players: "1-2", coverArtURL: cover, titleScreenURL: screenshot)
                game.favorite = entry.title == "Glass Harbor"
                context.insert(game)
                games.append(game)
            }
            try context.save()
            self.games = games
        }
    }

    /// Plain pictures standing in for scraped art.
    @MainActor enum Art {
        static func box(_ title: String, color: NSColor, size: CGSize, slanted: Bool = false) -> Data {
            png(size) { rect in
                let body = slanted ? rect.insetBy(dx: rect.width * 0.08, dy: 0) : rect
                color.setFill()
                NSBezierPath(rect: body).fill()
                if slanted {
                    (color.blended(withFraction: 0.5, of: .black) ?? color).setFill()
                    NSBezierPath(rect: CGRect(x: body.minX - rect.width * 0.08, y: 0, width: rect.width * 0.08, height: rect.height)).fill()
                }
                label(title, in: body.insetBy(dx: 20, dy: 20), size: min(size.width, size.height) / 7)
            }
        }

        static func logo(_ title: String, color: NSColor) -> Data {
            png(CGSize(width: 800, height: 300)) { rect in
                label(title, in: rect, size: 90, color: color.blended(withFraction: 0.4, of: .white) ?? .white)
            }
        }

        static func disc(color: NSColor) -> Data {
            png(CGSize(width: 600, height: 600)) { rect in
                NSColor(white: 0.85, alpha: 1).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 60, dy: 60)).fill()
                NSColor.clear.setFill()
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: rect.insetBy(dx: 260, dy: 260)).fill()
            }
        }

        static func cartridge(_ title: String, color: NSColor) -> Data {
            png(CGSize(width: 600, height: 560)) { rect in
                NSColor(white: 0.55, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10), xRadius: 30, yRadius: 30).fill()
                color.setFill()
                let labelRect = CGRect(x: 80, y: 180, width: 440, height: 320)
                NSBezierPath(rect: labelRect).fill()
                label(title, in: labelRect.insetBy(dx: 16, dy: 16), size: 60)
            }
        }

        private static func label(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor = .white) {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: color, .paragraphStyle: style
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let height = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin]).height
            string.draw(with: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                        options: [.usesLineFragmentOrigin])
        }

        private static func png(_ size: CGSize, draw: (CGRect) -> Void) -> Data {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            draw(CGRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            return rep.representation(using: .png, properties: [:]) ?? Data()
        }
    }
}

/// The Theme Editor's form and preview without its window and store, so
/// the snapshot never reads or writes the Themes folder.
private struct EditorStage: View {
    let page: ThemePreviewPage
    /// No controller hints: they need the gamepad monitor, which the
    /// snapshot doesn't start.
    @State private var theme: CabinetTheme = {
        var theme = CabinetTheme.unboxed
        theme.showsHints = false
        return theme
    }()
    @State private var selection: LibrarySelection = .allGames

    var body: some View {
        let sections = [CabinetSection(selection: .allGames, title: "All Games"),
                        CabinetSection(selection: .favorites, title: String(localized: "Favorites"))]
        HStack(spacing: 0) {
            ThemeEditorForm(theme: $theme)
                .frame(width: 400)
            Divider()
            ThemePreview(installed: .init(theme: theme), page: page, sections: sections, selection: $selection)
                .padding(20)
                .background(.black)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EditorForm: View {
    @State private var theme = CabinetTheme.unboxed

    var body: some View {
        ThemeEditorForm(theme: $theme)
            .scrollDisabled(true)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
