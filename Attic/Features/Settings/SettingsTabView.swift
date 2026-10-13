import SwiftUI

struct SettingsTabView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RetroArchSettingsView()
                .tabItem { Label("Emulators", systemImage: "arcade.stick.console") }
            BIOSSettingsView()
                .tabItem { Label("BIOS", systemImage: "cpu") }
            ControllerSettingsView()
                .tabItem { Label("Controller", systemImage: "gamecontroller") }
            ScreenScraperSettingsView()
                .tabItem { Label("ScreenScraper", systemImage: "photo.on.rectangle.angled") }
            TheGamesDBSettingsView()
                .tabItem { Label("TheGamesDB", systemImage: "text.book.closed") }
        }
        // One size for every tab: per-tab sizes made the window shrink on
        // the narrower tabs until the toolbar couldn't fit all six tabs,
        // and macOS hid the last one in an overflow menu.
        .frame(width: 700, height: 580)
    }
}
