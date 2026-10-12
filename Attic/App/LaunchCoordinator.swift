import AppKit
import Foundation
import Observation
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

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

    /// A game held back because its emulator's BIOS isn't there: launching
    /// would only crash or hang the emulator. Shown as an alert.
    struct MissingBIOS: Identifiable {
        let id = UUID()
        let game: Game
        let systemName: String
        let fileNames: [String]
        /// "Any model works, for example SCPH-39001 (US), …", when Attic knows which dumps do.
        let supportedDumps: String?
        /// Where the files go: the first missing one's folder.
        let folder: URL
    }
    var missingBIOS: MissingBIOS?
    private var currentSession: RunningGameSession?
    private let zippedROMExtractor = ZippedROMExtractor()

    /// Settings › Controller. Applied by configuring each emulator at
    /// launch — RetroArch's binds and quit combo, DuckStation's PowerOff
    /// hotkey — since emulators own the controller while a game runs.
    private let controllerSettingsStore: ControllerSettingsStore

    init(controllerSettingsStore: ControllerSettingsStore) {
        self.controllerSettingsStore = controllerSettingsStore
    }

    /// "Neo Geo free play" (Settings › General) — see `CoreLaunchOptions`.
    static let neoGeoFreePlayKey = "neoGeoFreePlay"

    private var neoGeoFreePlay: Bool {
        UserDefaults.standard.object(forKey: Self.neoGeoFreePlayKey) as? Bool ?? true
    }

    /// `checkingBIOS: false` is "Play Anyway" from the missing-BIOS alert,
    /// for dumps named differently from what Attic looks for.
    func play(game: Game, retroArchStore: RetroArchSettingsStore, checkingBIOS: Bool = true) {
        guard state == .idle || isFailed else { return }

        guard let target = LaunchTargetResolution.resolve(
            gameOverride: game.launchOverride,
            systemDefault: game.system?.defaultLaunchTarget
        ) else {
            state = .failed(String(localized: "No emulator configured for this game or its system."))
            return
        }

        if checkingBIOS, let missing = missingBIOS(for: game, target: target, biosFolder: retroArchStore.emulationFolderStore.folder.bios) {
            missingBIOS = missing
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
    /// Attic is still the app the user last touched: on a slow start
    /// (FinalBurn Neo spends seconds loading the Neo Geo BIOS) a click or
    /// controller press in Attic meanwhile keeps Attic in front, and
    /// RetroArch then sits paused in the background ("pause when not
    /// focused") with no controller input. Attic yields activation
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
            // DOSBox Pure likewise runs zipped DOS games as they are.
            let romURL = SystemTaxonomy.definition(for: systemID)?.category == .arcade || systemID == .dos
                ? game.romAbsoluteURL
                : zippedROMExtractor.resolvedROMURL(for: game.romAbsoluteURL)
            // Config, BIOS, saves and states all come from the Emulation
            // folder; the user's global retroarch.cfg is never touched.
            let folder = retroArchStore.emulationFolderStore.folder
            let systemSettings = SystemSettingsSupport.effective(
                game.system?.settings ?? SystemSettings(),
                system: systemID,
                retroLookByDefault: UserDefaults.standard.bool(forKey: ShaderPackStore.retroLookByDefaultKey)
            )
            let (configURL, appendConfigURL) = try folder.prepareRetroArchLaunch(
                for: systemID, controller: controllerSettingsStore.settings, systemSettings: systemSettings
            )
            try folder.setSystemCoreOptions(systemSettings, core: identifier)
            try folder.setRetroArchCoreOptions(CoreLaunchOptions.options(
                system: systemID, coreIdentifier: identifier, romURL: game.romAbsoluteURL, neoGeoFreePlay: neoGeoFreePlay
            ))
            return try RetroArchLauncher(retroArchBinaryURL: retroArchStore.binaryURL).launch(
                coreDylibURL: core.dylibURL, romURL: romURL, configURL: configURL, appendConfigURL: appendConfigURL,
                extraArguments: folder.retroArchShaderArguments(for: systemSettings)
            )

        case .emulatorProfile(let id):
            guard let profile = fetchEmulatorProfile(id: id, context: game.modelContext) else {
                throw LaunchError.profileNotFound
            }
            // Emulators Attic installed get their portable setup applied
            // (data in Emulation/Config, BIOS/saves/states shared); profiles
            // the user made by hand launch exactly as configured.
            var environment: [String: String] = [:]
            var extraArguments: [String] = []
            let systemSettings = game.system?.settings ?? SystemSettings()
            if let catalogID = profile.catalogEmulatorID,
               let emulator = EmulatorCatalog.standaloneEmulators.first(where: { $0.id == catalogID }) {
                environment = try retroArchStore.emulationFolderStore.folder.prepareStandaloneLaunch(
                    of: emulator, for: CanonicalSystemID(game.systemCanonicalID),
                    quitCombo: controllerSettingsStore.settings.quitWithSelectStart,
                    buttonMapping: controllerSettingsStore.settings.buttonMapping,
                    systemSettings: systemSettings
                )
                if emulator.id == EmulatorCatalog.dolphin.id {
                    extraArguments = SystemSettingsSupport.dolphinArguments(systemSettings)
                }
            }
            return try CustomEmulatorLauncher().launch(
                executableURL: profile.executableURL,
                argumentTemplate: profile.argumentTemplate,
                romURL: game.romAbsoluteURL,
                workingDirectoryURL: profile.workingDirectoryURL,
                environmentOverrides: environment,
                extraArguments: extraArguments
            )
        }
    }

    /// Required BIOS files `target` lacks. Emulator profiles the user made
    /// by hand are theirs to set up, so only Attic's own installs count.
    private func missingBIOS(for game: Game, target: LaunchTargetReference, biosFolder: URL) -> MissingBIOS? {
        if case .emulatorProfile(let id) = target,
           fetchEmulatorProfile(id: id, context: game.modelContext)?.catalogEmulatorID == nil {
            return nil
        }
        let systemID = CanonicalSystemID(game.systemCanonicalID)
        let missing = EmulatorSetupCoordinator.biosRequirements(for: systemID, target: target)
            .filter { $0.required && !$0.isPresent(in: biosFolder) }
        guard let first = missing.first else { return nil }
        let firstURL = biosFolder.appending(path: first.fileName)
        return MissingBIOS(
            game: game,
            systemName: game.system?.displayName ?? game.systemCanonicalID,
            fileNames: missing.map(\.fileName),
            supportedDumps: missing.lazy.compactMap(SystemFacts.supportedDumps).first,
            folder: first.isFolder ? firstURL : firstURL.deletingLastPathComponent()
        )
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
        // Back to the library (or Cabinet Mode) instead of leaving the user on
        // whatever app happens to be behind the emulator.
        NSApp.activate()
    }
}
