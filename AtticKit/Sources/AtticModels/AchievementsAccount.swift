import Foundation

/// A RetroAchievements account as emulators are given it: the user name
/// and the login token retroachievements.org handed out (never the
/// password), and whether to play in hardcore mode.
public struct AchievementsAccount: Sendable, Equatable {
    public let username: String
    public let token: String
    /// No save states, rewind, cheats or slow motion, for full points.
    public let hardcore: Bool

    public init(username: String, token: String, hardcore: Bool) {
        self.username = username
        self.token = token
        self.hardcore = hardcore
    }
}
