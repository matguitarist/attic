/// Which `LaunchTargetReference` actually applies for a game: a per-game
/// override always wins over the per-system default. Deliberately a tiny,
/// named, tested concept rather than an inline `??` scattered through the
/// app layer, since it documents the one precedence rule the whole launch
/// flow depends on.
public enum LaunchTargetResolution {
    public static func resolve(
        gameOverride: LaunchTargetReference?,
        systemDefault: LaunchTargetReference?
    ) -> LaunchTargetReference? {
        gameOverride ?? systemDefault
    }
}
