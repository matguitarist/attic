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
        /// "Any model works, for example scph39001.bin, …", when Attic knows which dumps do.
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
            AppLog.post(.error, "Couldn't launch “\(game.title)”: no emulator is set for it or for \(game.systemCanonicalID).")
            return
        }

        let folder = retroArchStore.emulationFolderStore.folder
        if checkingBIOS {
            folder.movePS2BIOSIntoPlace()
        }
        if checkingBIOS, let missing = missingBIOS(for: game, target: target, biosFolder: folder.bios) {
            missingBIOS = missing
            AppLog.post(.warning, "“\(game.title)” needs BIOS files that aren't in \(missing.folder.path): \(missing.fileNames.joined(separator: ", ")).")
            return
        }

        state = .launching
        let emulator = emulatorName(for: target, game: game)
        AppLog.post(.info, "Launching “\(game.title)” (\(game.systemCanonicalID)) with \(emulator.description): \(game.romAbsoluteURL.path)")

        let session: RunningGameSession
        do {
            session = try launch(target, game: game, retroArchStore: retroArchStore, onOutput: Self.outputLogger(source: emulator.source))
        } catch {
            state = .failed(String(localized: "Couldn't launch: \(error.localizedDescription)"))
            AppLog.post(.error, "Couldn't launch “\(game.title)”: \(error.localizedDescription)")
            return
        }
        AppLog.post(.debug, "Command: \(session.commandLine.map(Self.shellQuoted).joined(separator: " "))")

        currentSession = session
        state = .running(gameID: game.persistentModelID)
        let playSession = recordSessionStarted(game: game, launchMethod: target)

        Task {
            let status = await session.waitUntilExit()
            logExit(of: game, emulator: emulator.source, status: status, startedAt: playSession?.startedAt)
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
        for attempt in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            guard session.isRunning else { return }
            guard let app = NSRunningApplication(processIdentifier: session.processIdentifier) else { continue }
            if app.isActive {
                if attempt > 0 { AppLog.post(.debug, "The emulator came to the front after \(Double(attempt + 1) / 2) s.") }
                return
            }
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        AppLog.post(.warning, "The emulator never came to the front, so it may sit paused in the background without controller input. Click its window to play.")
    }

    /// Who's launching, for the log: "RetroArch (MAME)", source "RetroArch".
    private func emulatorName(for target: LaunchTargetReference, game: Game) -> (description: String, source: String) {
        switch target {
        case .retroArchCore(let identifier):
            ("RetroArch (\(identifier))", "RetroArch")
        case .emulatorProfile(let id):
            fetchEmulatorProfile(id: id, context: game.modelContext).map { ($0.name, $0.name) } ?? ("an emulator", "Emulator")
        }
    }

    /// Turns each line an emulator prints into a log entry.
    private nonisolated static func outputLogger(source: String) -> @Sendable (String) -> Void {
        { line in
            let (level, message) = EmulatorOutput.parse(line)
            AppLog.post(level, message, source: source)
        }
    }

    private func logExit(of game: Game, emulator: String, status: Int32, startedAt: Date?) {
        let seconds = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        let duration = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        if status != 0 {
            AppLog.post(.error, "\(emulator) quit with error code \(status) after \(duration) playing “\(game.title)”. The messages above usually say why.")
        } else if seconds < 5 {
            AppLog.post(.warning, "\(emulator) closed \(duration) after starting “\(game.title)”: the game probably didn't load. The messages above usually say why.")
        } else {
            AppLog.post(.info, "\(emulator) quit after \(duration) playing “\(game.title)”.")
        }
    }

    private nonisolated static func shellQuoted(_ argument: String) -> String {
        argument.contains(where: { " '\"$\\()&;".contains($0) }) ? "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'" : argument
    }

    private func launch(
        _ target: LaunchTargetReference,
        game: Game,
        retroArchStore: RetroArchSettingsStore,
        onOutput: @escaping @Sendable (String) -> Void
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
            // So do EasyRPG (zipped RPG Maker games) and game folders
            // (ScummVM, Quake), which get the file inside that the core reads.
            let isFolder = (try? game.romAbsoluteURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let romURL = isFolder
                ? SystemROMExtensions.launchFile(forGameFolder: game.romAbsoluteURL)
                : SystemTaxonomy.definition(for: systemID)?.category == .arcade || systemID == .dos || systemID == .easyrpg
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
                for: systemID, controller: controllerSettingsStore.settings, systemSettings: systemSettings,
                achievements: RetroAchievementsStore.currentAccount
            )
            try folder.setSystemCoreOptions(systemSettings, core: identifier)
            try folder.setRetroArchCoreOptions(CoreLaunchOptions.options(
                system: systemID, coreIdentifier: identifier, romURL: game.romAbsoluteURL, neoGeoFreePlay: neoGeoFreePlay
            ))
            return try RetroArchLauncher(retroArchBinaryURL: retroArchStore.binaryURL).launch(
                coreDylibURL: core.dylibURL, romURL: romURL, configURL: configURL, appendConfigURL: appendConfigURL,
                extraArguments: folder.retroArchShaderArguments(for: systemSettings),
                onOutput: onOutput
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
                    systemSettings: systemSettings,
                    achievements: RetroAchievementsStore.currentAccount
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
                extraArguments: extraArguments,
                onOutput: onOutput
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
        return MissingBIOS(
            game: game,
            systemName: game.system?.displayName ?? game.systemCanonicalID,
            fileNames: missing.map(\.fileName),
            supportedDumps: missing.lazy.compactMap(SystemFacts.supportedDumps).first,
            folder: first.folder(in: biosFolder)
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
