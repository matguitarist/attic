import Foundation

/// What to launch a game with: either a RetroArch core, or a user-defined
/// custom emulator profile. This is the small, persisted/storable value —
/// distinct from `ResolvedLaunchTarget` (defined in RomsBoxEmulation), which
/// is the concrete executable+arguments computed from this reference at
/// launch time against current filesystem state.
public enum LaunchTargetReference: Sendable, Hashable, Codable {
    /// `coreIdentifier` matches a RetroArch core's filename without extension,
    /// e.g. "snes9x_libretro" — stable across RetroArch reinstalls/updates,
    /// unlike an absolute path.
    case retroArchCore(coreIdentifier: String)
    case emulatorProfile(id: UUID)
}
