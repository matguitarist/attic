import Foundation
import SwiftData
import AtticModels

/// Append-only log of one launch. Feeds `Game.playCount`/`totalPlaytimeSeconds`
/// aggregates (updated by `PlayHistoryRecorder` in the app layer, Phase 9)
/// and is useful audit/debugging data in its own right.
@Model
public final class PlaySession {
    public var startedAt: Date
    public var endedAt: Date?
    public var launchMethodRaw: String
    public var game: Game?

    public init(game: Game?, launchMethod: LaunchTargetReference, startedAt: Date = .now) {
        self.game = game
        self.startedAt = startedAt
        self.endedAt = nil
        switch launchMethod {
        case .retroArchCore:
            self.launchMethodRaw = "retroArchCore"
        case .emulatorProfile:
            self.launchMethodRaw = "emulatorProfile"
        }
    }

    /// A game run by something other than an emulator: "steam".
    public init(game: Game?, launchMethodRaw: String, startedAt: Date = .now) {
        self.game = game
        self.startedAt = startedAt
        self.endedAt = nil
        self.launchMethodRaw = launchMethodRaw
    }
}
