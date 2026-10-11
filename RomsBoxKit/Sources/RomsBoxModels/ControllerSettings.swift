import Foundation

/// Which face button confirms — the one real difference between the two
/// families of controllers people grow up with.
public enum ButtonLayout: String, Sendable, Codable, CaseIterable {
    /// Xbox / PlayStation: the bottom button (A / Cross) confirms, the
    /// right one (B / Circle) goes back.
    case classic
    /// Nintendo / Switch: the right button confirms, the bottom one goes
    /// back.
    case nintendo
}

/// How the controller behaves in RomsBox and in games RomsBox launches.
/// One global setting, saved and restored as a whole through profiles.
public struct ControllerSettings: Sendable, Codable, Hashable {
    public var layout: ButtonLayout
    /// Which controller button presses each RetroPad button in games
    /// (RetroArch, and DuckStation's PlayStation pad).
    public var buttonMapping: ButtonMapping
    /// Select + Start quits the running game.
    public var quitWithSelectStart: Bool
    /// The left stick also works as the D-pad in RetroArch games, for
    /// systems whose own pad had no stick.
    public var leftStickAsDPad: Bool

    public init(
        layout: ButtonLayout = .classic,
        buttonMapping: ButtonMapping = .default,
        quitWithSelectStart: Bool = true,
        leftStickAsDPad: Bool = false
    ) {
        self.layout = layout
        self.buttonMapping = buttonMapping
        self.quitWithSelectStart = quitWithSelectStart
        self.leftStickAsDPad = leftStickAsDPad
    }

    public static let `default` = ControllerSettings()

    // Missing keys fall back to defaults, so settings saved by an older
    // RomsBox (or a hand-edited profiles file) still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ControllerSettings.default
        layout = (try? container.decode(ButtonLayout.self, forKey: .layout)) ?? defaults.layout
        buttonMapping = (try? container.decodeIfPresent(ButtonMapping.self, forKey: .buttonMapping)) ?? defaults.buttonMapping
        quitWithSelectStart = try container.decodeIfPresent(Bool.self, forKey: .quitWithSelectStart) ?? defaults.quitWithSelectStart
        leftStickAsDPad = try container.decodeIfPresent(Bool.self, forKey: .leftStickAsDPad) ?? defaults.leftStickAsDPad
    }
}

/// A named, saved set of controller settings.
public struct ControllerProfile: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var settings: ControllerSettings

    public init(id: UUID = UUID(), name: String, settings: ControllerSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}
