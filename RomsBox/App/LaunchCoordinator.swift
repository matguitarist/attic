import Foundation
import Observation
import SwiftData
import RomsBoxModels
import RomsBoxPersistence
import RomsBoxEmulation

/// Resolves a game's launch target and runs it. Only RetroArch cores exist
/// as of Phase 7 — the per-game-override/per-system-default precedence and
/// custom emulator profiles arrive in Phase 8's EmulatorResolver.
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

    func playWithRetroArch(game: Game, core: RetroArchCoreInfo, retroArchBinaryURL: URL) {
        guard state == .idle || isFailed else { return }
        state = .launching

        let launcher = RetroArchLauncher(retroArchBinaryURL: retroArchBinaryURL)
        let session: RunningGameSession
        do {
            session = try launcher.launch(coreDylibURL: core.dylibURL, romURL: game.romAbsoluteURL)
        } catch {
            state = .failed("Couldn't launch RetroArch: \(error.localizedDescription)")
            return
        }

        currentSession = session
        state = .running(gameID: game.persistentModelID)

        Task {
            _ = await session.waitUntilExit()
            recordSessionEnded(game: game)
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func recordSessionEnded(game: Game) {
        game.playCount += 1
        game.lastPlayedDate = .now
        try? game.modelContext?.save()
        currentSession = nil
        state = .idle
    }
}
