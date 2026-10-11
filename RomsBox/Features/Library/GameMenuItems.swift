import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence

/// "Launch With" menu contents — per-game override of the system's default
/// core/emulator. Shared by the grid's context menu, the inspector, and
/// the Game menu so all three always offer the same choices.
struct LaunchWithMenuItems: View {
    let game: Game

    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Query(sort: \EmulatorProfile.name) private var customEmulatorProfiles: [EmulatorProfile]

    var body: some View {
        if game.launchOverride != nil {
            Button("Use System Default") {
                game.launchOverride = nil
                try? game.modelContext?.save()
            }
            Divider()
        }

        if let systemID = game.system?.systemID {
            let cores = retroArchStore.cores(for: systemID)
            if !cores.isEmpty {
                Section("RetroArch Cores") {
                    ForEach(cores) { core in
                        Toggle(core.displayName, isOn: overrideBinding(.retroArchCore(coreIdentifier: core.coreIdentifier)))
                    }
                }
            }

            let matchingProfiles = customEmulatorProfiles.filter { $0.assignedSystemIDs.contains(systemID) }
            if !matchingProfiles.isEmpty {
                Section("Custom Emulators") {
                    ForEach(matchingProfiles) { profile in
                        Toggle(profile.name, isOn: overrideBinding(.emulatorProfile(id: profile.id)))
                    }
                }
            }
        }
    }

    /// A Toggle per choice (rather than a plain Button) so the menu shows a
    /// native checkmark next to whichever override is currently active.
    private func overrideBinding(_ target: LaunchTargetReference) -> Binding<Bool> {
        Binding(
            get: { game.launchOverride == target },
            set: { isOn in
                game.launchOverride = isOn ? target : nil
                try? game.modelContext?.save()
            }
        )
    }
}

/// Single-game "Scrape Info" menu contents.
struct ScrapeMenuItems: View {
    let game: Game

    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator
    @Environment(ScreenScraperCredentialsStore.self) private var screenScraperCredentialsStore
    @Environment(TheGamesDBCredentialsStore.self) private var theGamesDBCredentialsStore

    var body: some View {
        Button("ScreenScraper") {
            Task { await scrapeCoordinator.scrapeUsingScreenScraper(game: game, credentials: screenScraperCredentialsStore.credentials) }
        }
        .disabled(!screenScraperCredentialsStore.isConfigured)

        Button("TheGamesDB") {
            Task { await scrapeCoordinator.scrapeUsingTheGamesDB(game: game, credentials: theGamesDBCredentialsStore.credentials) }
        }
        .disabled(!theGamesDBCredentialsStore.isConfigured)
    }
}
