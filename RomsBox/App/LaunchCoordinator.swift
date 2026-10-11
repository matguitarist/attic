import AppKit
import Foundation
import Observation
import SwiftData
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxEmulation

/// Resolves a game's launch target (per-game override, else per-system
/// default, via `LaunchTargetResolution`) and runs it through whichever
/// launcher applies, then records the session.
@Observable
@MainActor
final class LaunchCoordinator {
    enum State: Equatable {
        case idle
        case launching
        case running(gameID: PersistentIdentifier)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var currentSession: RunningGameSession?
    private let zippedROMExtractor = ZippedROMExtractor()

    /// "Quit games with Select + Start" (Settings › General). Applied by
    /// configuring each emulator's own quit combo at launch — RetroArch's
    /// `input_quit_gamepad_combo`, DuckStation's PowerOff hotkey — since
    /// emulators own the controller while a game runs.
    static let quitComboEnabledKey = "quitGameWithSelectStart"

    private var quitComboEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.quitComboEnabledKey) as? Bool ?? true
    }

    /// "Neo Geo free play" (Settings › General) — see `CoreLaunchOptions`.
    static let neoGeoFreePlayKey = "neoGeoFreePlay"

    private var neoGeoFreePlay: Bool {
        UserDefaults.standard.object(forKey: Self.neoGeoFreePlayKey) as? Bool ?? true
    }

    func play(game: Game, retroArchStore: RetroArchSettingsStore) {
        guard state == .idle || isFailed else { return }

        guard let target = LaunchTargetResolution.resolve(
            gameOverride: game.launchOverride,
            systemDefault: game.system?.defaultLaunchTarget
        ) else {
            state = .failed(String(localized: "No emulator configured for this game or its system."))
            return
        }

        state = .launching

        let session: RunningGameSession
        do {
            session = try launch(target, game: game, retroArchStore: retroArchStore)
        } catch {
            state = .failed(String(localized: "Couldn't launch: \(error.localizedDescription)"))
            return
        }

        currentSession = session
        state = .running(gameID: game.persistentModelID)
        let playSession = recordSessionStarted(game: game, launchMethod: target)

        Task {
            _ = await session.waitUntilExit()
            recordSessionEnded(game: game, playSession: playSession)
        }
        Task { await handFocus(to: session) }
    }

    /// Brings the emulator to the front once it's up. Emulators activate
    /// themselves when their window opens, but macOS only allows that while
    /// RomsBox is still the app the user last touched: on a slow start
    /// (FinalBurn Neo spends seconds loading the Neo Geo BIOS) a click or
    /// controller press in RomsBox meanwhile keeps RomsBox in front, and
    /// RetroArch then sits paused in the background ("pause when not
    /// focused") with no controller input. RomsBox yields activation
    /// explicitly instead. Stops after the first success, so switching away
    /// mid-game is never undone.
    private func handFocus(to session: RunningGameSession) async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            guard session.isRunning else { return }
            guard let app = NSRunningApplication(processIdentifier: session.processIdentifier) else { continue }
            if app.isActive { return }
            NSApp.yieldActivation(to: app)
            app.activate()
        }
    }

    private func launch(
        _ target: LaunchTargetReference,
        game: Game,
        retroArchStore: RetroArchSettingsStore
    ) throws -> RunningGameSession {
        switch target {
        case .retroArchCore(let identifier):
            guard let core = retroArchStore.core(withIdentifier: identifier) else {
                throw LaunchError.coreNotInstalled(identifier)
            }
            // Zipped ROMs need resolving to a real extracted file first —
            // see ZippedROMExtractor for why passing the zip straight to
            // RetroArch's command line is unreliable.
            // Arcade ROMs are multi-file sets the core must receive as the
            // archive itself (FinalBurn Neo reads the zip) — never extract.
            let systemID = CanonicalSystemID(game.systemCanonicalID)
            let romURL = SystemTaxonomy.definition(for: systemID)?.category == .arcade
                ? game.romAbsoluteURL
                : zippedROMExtractor.resolvedROMURL(for: game.romAbsoluteURL)
            // Config, BIOS, saves and states all come from the Emulation
            // folder; the user's global retroarch.cfg is never touched.
            let folder = retroArchStore.emulationFolderStore.folder
            let (configURL, appendConfigURL) = try folder.prepareRetroArchLaunch(for: systemID, quitCombo: quitComboEnabled)
            try folder.setRetroArchCoreOptions(CoreLaunchOptions.options(
                system: systemID, coreIdentifier: identifier, romURL: game.romAbsoluteURL, neoGeoFreePlay: neoGeoFreePlay
            ))
            return try RetroArchLauncher(retroArchBinaryURL: retroArchStore.binaryURL)
                .launch(coreDylibURL: core.dylibURL, romURL: romURL, configURL: configURL, appendConfigURL: appendConfigURL)

        case .emulatorProfile(let id):
            guard let profile = fetchEmulatorProfile(id: id, context: game.modelContext) else {
                throw LaunchError.profileNotFound
            }
            // Emulators RomsBox installed get their portable setup applied
            // (data in Emulation/Config, BIOS/saves/states shared); profiles
            // the user made by hand launch exactly as configured.
            var environment: [String: String] = [:]
            if let catalogID = profile.catalogEmulatorID,
               let emulator = EmulatorCatalog.standaloneEmulators.first(where: { $0.id == catalogID }) {
                environment = try retroArchStore.emulationFolderStore.folder
                    .prepareStandaloneLaunch(of: emulator, for: CanonicalSystemID(game.systemCanonicalID), quitCombo: quitComboEnabled)
            }
            return try CustomEmulatorLauncher().launch(
                executableURL: profile.executableURL,
                argumentTemplate: profile.argumentTemplate,
                romURL: game.romAbsoluteURL,
                workingDirectoryURL: profile.workingDirectoryURL,
                environmentOverrides: environment
            )
        }
    }

    private enum LaunchError: LocalizedError {
        case coreNotInstalled(String)
        case profileNotFound

        var errorDescription: String? {
            switch self {
            case .coreNotInstalled(let identifier):
                String(localized: "The core “\(identifier)” is no longer installed.")
            case .profileNotFound:
                String(localized: "The assigned custom emulator profile no longer exists.")
            }
        }
    }

    private func fetchEmulatorProfile(id: UUID, context: ModelContext?) -> EmulatorProfile? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<EmulatorProfile>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// Inserts the append-only `PlaySession` audit row for this launch.
    /// Aggregates (`playCount`/`lastPlayedDate`/`totalPlaytimeSeconds`) are
    /// only finalized in `recordSessionEnded`, once the actual duration is
    /// known.
    private func recordSessionStarted(game: Game, launchMethod: LaunchTargetReference) -> PlaySession? {
        guard let context = game.modelContext else { return nil }
        let session = PlaySession(game: game, launchMethod: launchMethod)
        context.insert(session)
        try? context.save()
        return session
    }

    private func recordSessionEnded(game: Game, playSession: PlaySession?) {
        let now = Date.now
        game.playCount += 1
        game.lastPlayedDate = now
        if let playSession {
            playSession.endedAt = now
            game.totalPlaytimeSeconds += max(0, now.timeIntervalSince(playSession.startedAt))
        }
        try? game.modelContext?.save()
        currentSession = nil
        state = .idle
        // Back to the library (or Big Box) instead of leaving the user on
        // whatever app happens to be behind the emulator.
        NSApp.activate()
    }
}
