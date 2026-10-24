import SwiftUI

struct SettingsTabView: View {
    enum Tab: String {
        case general, cabinet, collections, emulators, bios, controller, screenScraper, theGamesDB, steamGridDB, emuMovies
    }

    /// The tab shown, which a menu item can set before opening Settings.
    static let selectionKey = "settingsTab"
    @AppStorage(Self.selectionKey) private var selection = Tab.general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            CabinetSettingsView()
                .tabItem { Label("Cabinet Mode", systemImage: "play.tv") }
                .tag(Tab.cabinet)
            CollectionsSettingsView()
                .tabItem { Label("Collections", systemImage: "rectangle.stack") }
                .tag(Tab.collections)
            RetroArchSettingsView()
                .tabItem { Label("Emulators", systemImage: "arcade.stick.console") }
                .tag(Tab.emulators)
            BIOSSettingsView()
                .tabItem { Label("BIOS", systemImage: "cpu") }
                .tag(Tab.bios)
            ControllerSettingsView()
                .tabItem { Label("Controller", systemImage: "gamecontroller") }
                .tag(Tab.controller)
            ScreenScraperSettingsView()
                .tabItem { Label("ScreenScraper", systemImage: "photo.on.rectangle.angled") }
                .tag(Tab.screenScraper)
            TheGamesDBSettingsView()
                .tabItem { Label("TheGamesDB", systemImage: "text.book.closed") }
                .tag(Tab.theGamesDB)
            SteamGridDBSettingsView()
                .tabItem { Label("SteamGridDB", systemImage: "square.grid.3x3") }
                .tag(Tab.steamGridDB)
            EmuMoviesSettingsView()
                .tabItem { Label("EmuMovies", systemImage: "film.stack") }
                .tag(Tab.emuMovies)
        }
        // One size for every tab: per-tab sizes made the window shrink on
        // the narrower tabs until the toolbar couldn't fit all six tabs,
        // and macOS hid the last one in an overflow menu.
        .frame(width: 860, height: 580)
    }
}
