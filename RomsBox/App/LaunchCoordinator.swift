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

    func play(game: Game, retroArchStore: RetroArchSettingsStore) {
        guard state == .idle || isFailed else { return }

        guard let target = LaunchTargetResolution.resolve(
            gameOverride: game.launchOverride,
            systemDefault: game.system?.defaultLaunchTarget
        ) else {
            state = .failed("No emulator configured for this game or its system.")
            return
        }

        state = .launching

        let session: RunningGameSession
        do {
            session = try launch(target, game: game, retroArchStore: retroArchStore)
        } catch {
            state = .failed("Couldn't launch: \(error.localizedDescription)")
            return
        }

        currentSession = session
        state = .running(gameID: game.persistentModelID)
        let playSession = recordSessionStarted(game: game, launchMethod: target)

        Task {
            _ = await session.waitUntilExit()
            recordSessionEnded(game: game, playSession: playSession)
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
            let romURL = zippedROMExtractor.resolvedROMURL(for: game.romAbsoluteURL)
            return try RetroArchLauncher(retroArchBinaryURL: retroArchStore.binaryURL)
                .launch(coreDylibURL: core.dylibURL, romURL: romURL)

        case .emulatorProfile(let id):
            guard let profile = fetchEmulatorProfile(id: id, context: game.modelContext) else {
                throw LaunchError.profileNotFound
            }
            return try CustomEmulatorLauncher().launch(
                executableURL: profile.executableURL,
                argumentTemplate: profile.argumentTemplate,
                romURL: game.romAbsoluteURL,
                workingDirectoryURL: profile.workingDirectoryURL
            )
        }
    }

    private enum LaunchError: LocalizedError {
        case coreNotInstalled(String)
        case profileNotFound

        var errorDescription: String? {
            switch self {
            case .coreNotInstalled(let identifier):
                "The core \"\(identifier)\" is no longer installed."
            case .profileNotFound:
                "The assigned custom emulator profile no longer exists."
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
    }
}
