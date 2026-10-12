import Foundation

/// Per-system emulator settings (right-click a system › System Settings…).
/// Every value is optional: `nil` means "Default", where Attic leaves the
/// emulator's own setting alone. Which ones apply depends on the emulator
/// the system runs in; see `SystemSettingsSupport` in AtticEmulation.
public struct SystemSettings: Codable, Hashable, Sendable {
    /// A RetroArch shader preset, applied for this system's games only.
    public enum Look: String, Codable, CaseIterable, Sendable {
        /// No shader at all: plain pixels, even if RetroArch has a preset.
        case none
        /// Crisp pixels without shimmering at non-integer sizes.
        case sharp
        /// Scanlines and a shadow mask, like a TV.
        case crt
        /// The same with the curved glass of an old TV.
        case crtCurved
        /// A handheld's pixel grid.
        case lcd
    }

    public var look: Look?
    /// A shader preset picked from the shader library (relative to the
    /// pack, e.g. "crt/crt-royale.slangp") or the user's own file (an
    /// absolute path). Takes the place of `look` when set.
    public var shaderPreset: String?
    /// Scale only by whole multiples, so every pixel is the same size.
    public var integerScaling: Bool?
    /// The 3D renderer's resolution, as a multiple of the console's.
    public var internalResolution: Int?
    /// Renders 3D games wider instead of stretching them.
    public var widescreen: Bool?
    /// PlayStation geometry correction (PGXP): no more wobbling polygons.
    public var geometryCorrection: Bool?
    /// Draws every sprite, removing the flicker of 8- and 16-bit consoles.
    public var unlimitedSprites: Bool?
    /// Game Boy Advance screen colors and frame blending.
    public var lcdColors: Bool?
    /// Frames of run-ahead, which removes the console's own input lag. 0 is off.
    public var runAheadFrames: Int?
    public var rewind: Bool?
    /// Saves a state on quit and loads it at the next launch.
    public var resume: Bool?

    public init() {}

    public var isEmpty: Bool { self == SystemSettings() }
}
