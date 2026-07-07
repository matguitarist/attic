import SwiftUI

struct SettingsTabView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            RetroArchSettingsView()
                .tabItem { Label("RetroArch", systemImage: "gamecontroller") }
            EmulatorProfilesSettingsView()
                .tabItem { Label("Custom Emulators", systemImage: "puzzlepiece.extension") }
            ScreenScraperSettingsView()
                .tabItem { Label("ScreenScraper", systemImage: "photo.on.rectangle.angled") }
            TheGamesDBSettingsView()
                .tabItem { Label("TheGamesDB", systemImage: "text.book.closed") }
        }
    }
}
