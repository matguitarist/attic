import Foundation

/// A button on the player's controller, named by position so it means the
/// same thing on every pad (Xbox's A, PlayStation's Cross and Switch's B
/// are all `bottom`) — the way GameController reports them.
public enum PhysicalButton: String, Sendable, Codable, CaseIterable, Hashable {
    case bottom, right, left, top
    case l1, r1, l2, r2, l3, r3
    case select, start
    case dpadUp, dpadDown, dpadLeft, dpadRight

    /// RetroArch's button number for it with the `mfi` (GameController)
    /// joypad driver, which numbers buttons by libretro's joypad IDs —
    /// `mfi_joypad.m` sets bit `RETRO_DEVICE_ID_JOYPAD_*` per element.
    public var retroArchMFiIndex: Int {
        switch self {
        case .bottom: 0
        case .left: 1
        case .select: 2
        case .start: 3
        case .dpadUp: 4
        case .dpadDown: 5
        case .dpadLeft: 6
        case .dpadRight: 7
        case .right: 8
        case .top: 9
        case .l1: 10
        case .r1: 11
        case .l2: 12
        case .r2: 13
        case .l3: 14
        case .r3: 15
        }
    }

    /// SDL's name for it, as DuckStation writes bindings (`SDL-0/<name>`).
    public var sdlName: String {
        switch self {
        case .bottom: "A"
        case .right: "B"
        case .left: "X"
        case .top: "Y"
        case .l1: "LeftShoulder"
        case .r1: "RightShoulder"
        case .l2: "+LeftTrigger"
        case .r2: "+RightTrigger"
        case .l3: "LeftStick"
        case .r3: "RightStick"
        case .select: "Back"
        case .start: "Start"
        case .dpadUp: "DPadUp"
        case .dpadDown: "DPadDown"
        case .dpadLeft: "DPadLeft"
        case .dpadRight: "DPadRight"
        }
    }

    public var isTrigger: Bool { self == .l2 || self == .r2 }
}

/// RetroArch's standard controller (the RetroPad, laid out like a Super
/// Nintendo pad) — what every core's controls are defined against, and so
/// the one set of buttons a mapping needs to cover.
public enum RetroPadButton: String, Sendable, Codable, CaseIterable, Hashable, CodingKeyRepresentable {
    case b, a, y, x
    case l, r, l2, r2, l3, r3
    case select, start
    case up, down, left, right

    /// Where RetroArch puts it by default: by position, like the console's
    /// own pad.
    public var defaultPhysical: PhysicalButton {
        switch self {
        case .b: .bottom
        case .a: .right
        case .y: .left
        case .x: .top
        case .l: .l1
        case .r: .r1
        case .l2: .l2
        case .r2: .r2
        case .l3: .l3
        case .r3: .r3
        case .select: .select
        case .start: .start
        case .up: .dpadUp
        case .down: .dpadDown
        case .left: .dpadLeft
        case .right: .dpadRight
        }
    }

    /// The `input_playerN_<name>_btn` part of RetroArch's bind keys.
    public var retroArchName: String { rawValue }

    /// The matching PlayStation button, as DuckStation's `[Pad1]` keys name
    /// them (RetroPad B/A/Y/X sit where Cross/Circle/Square/Triangle do).
    public var duckStationName: String {
        switch self {
        case .b: "Cross"
        case .a: "Circle"
        case .y: "Square"
        case .x: "Triangle"
        case .l: "L1"
        case .r: "R1"
        case .l2: "L2"
        case .r2: "R2"
        case .l3: "L3"
        case .r3: "R3"
        case .select: "Select"
        case .start: "Start"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// Which controller button presses each RetroPad button in games. Only
/// changes from the default (positional) layout are stored.
public struct ButtonMapping: Sendable, Codable, Hashable {
    public var overrides: [RetroPadButton: PhysicalButton]

    public init(overrides: [RetroPadButton: PhysicalButton] = [:]) {
        self.overrides = overrides.filter { $0.key.defaultPhysical != $0.value }
    }

    public static let `default` = ButtonMapping()

    /// A/B and X/Y by label instead of position: the button labeled A on an
    /// Xbox-style pad (the bottom one) acts as the console's A.
    public static let faceButtonsSwapped = ButtonMapping(overrides: [.b: .right, .a: .bottom, .y: .top, .x: .left])

    public var isDefault: Bool { overrides.isEmpty }

    public func physical(for button: RetroPadButton) -> PhysicalButton {
        overrides[button] ?? button.defaultPhysical
    }

    public mutating func set(_ physical: PhysicalButton, for button: RetroPadButton) {
        overrides[button] = physical == button.defaultPhysical ? nil : physical
    }
}

/// Settings RomsBox writes into an emulator's own config, tracked so they
/// can be taken back. Emulators save their whole config on exit, so a value
/// RomsBox stops setting would otherwise stay forever. On each launch:
/// keys RomsBox wants are written; keys it wrote last time but no longer
/// wants are reset — but only if they still hold RomsBox's value, so
/// anything the user changed in the emulator meanwhile is left alone.
public enum OwnedSettings {
    public static func reconcile(
        desired: [(key: String, value: String)],
        previouslyWritten: [String: String],
        current: [String: String],
        resetValue: (String) -> String?
    ) -> (write: [(key: String, value: String)], written: [String: String]) {
        let desiredKeys = Set(desired.map(\.key))
        var write = desired
        for (key, value) in previouslyWritten.sorted(by: { $0.key < $1.key })
        where !desiredKeys.contains(key) && current[key] == value {
            if let reset = resetValue(key) { write.append((key, reset)) }
        }
        return (write, Dictionary(desired.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last }))
    }
}
