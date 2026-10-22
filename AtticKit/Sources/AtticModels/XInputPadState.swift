import Foundation

/// Buttons in an XInput (Xbox 360 wired protocol) input report, as the
/// little-endian 16-bit mask at bytes 2–3.
public struct XInputButtons: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let dpadUp        = XInputButtons(rawValue: 1 << 0)
    public static let dpadDown      = XInputButtons(rawValue: 1 << 1)
    public static let dpadLeft      = XInputButtons(rawValue: 1 << 2)
    public static let dpadRight     = XInputButtons(rawValue: 1 << 3)
    public static let start         = XInputButtons(rawValue: 1 << 4)
    public static let back          = XInputButtons(rawValue: 1 << 5)
    public static let leftThumb     = XInputButtons(rawValue: 1 << 6)
    public static let rightThumb    = XInputButtons(rawValue: 1 << 7)
    public static let leftShoulder  = XInputButtons(rawValue: 1 << 8)
    public static let rightShoulder = XInputButtons(rawValue: 1 << 9)
    public static let guide         = XInputButtons(rawValue: 1 << 10)
    public static let a             = XInputButtons(rawValue: 1 << 12)
    public static let b             = XInputButtons(rawValue: 1 << 13)
    public static let x             = XInputButtons(rawValue: 1 << 14)
    public static let y             = XInputButtons(rawValue: 1 << 15)
}

/// One decoded XInput input report.
///
/// Wired Xbox 360–protocol pads (and pads emulating one over USB, such as
/// the Amazon Luna controller) expose a vendor-specific USB interface
/// (class 0xFF, subclass 0x5D, protocol 0x01) rather than a HID one, so
/// neither GameController nor IOHIDManager ever sees them on macOS — the
/// app has to read and decode these 20-byte reports itself:
///
///     [0] 0x00 message type   [1] 0x14 length
///     [2–3] buttons (LE)      [4] left trigger   [5] right trigger
///     [6–7] left X (LE i16)   [8–9] left Y (LE i16, up = positive)
///     [10–11] right X         [12–13] right Y    [14–19] unused
public struct XInputPadState: Sendable, Equatable {
    public var buttons: XInputButtons
    public var leftStickX: Int16
    public var leftStickY: Int16
    /// 0 (released) to 255 (fully pulled).
    public var leftTrigger: UInt8
    public var rightTrigger: UInt8

    public static let neutral = XInputPadState(buttons: [], leftStickX: 0, leftStickY: 0)

    public init(buttons: XInputButtons, leftStickX: Int16, leftStickY: Int16, leftTrigger: UInt8 = 0, rightTrigger: UInt8 = 0) {
        self.buttons = buttons
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
    }

    /// The triggers pulled past halfway, as presses of L2 and R2.
    public var leftTriggerPressed: Bool { leftTrigger >= 128 }
    public var rightTriggerPressed: Bool { rightTrigger >= 128 }

    /// Returns `nil` for anything that isn't an input report — the same
    /// pipe also carries short status messages (LED state, rumble acks)
    /// that start with a different type byte.
    public init?(report: [UInt8]) {
        guard report.count >= 10, report[0] == 0x00, report[1] >= 0x0A else { return nil }
        func u16(_ index: Int) -> UInt16 { UInt16(report[index]) | UInt16(report[index + 1]) << 8 }
        buttons = XInputButtons(rawValue: u16(2))
        leftTrigger = report[4]
        rightTrigger = report[5]
        leftStickX = Int16(bitPattern: u16(6))
        leftStickY = Int16(bitPattern: u16(8))
    }

    /// D-pad and left stick combined into grid directions. The stick needs
    /// to be pushed about halfway before it counts, so resting drift (the
    /// probe saw a pad idle at X = -1) never registers as a press.
    public func heldDirections(stickThreshold: Int16 = 16_384) -> Set<GridMoveDirection> {
        var held: Set<GridMoveDirection> = []
        if buttons.contains(.dpadUp) || leftStickY > stickThreshold { held.insert(.up) }
        if buttons.contains(.dpadDown) || leftStickY < -stickThreshold { held.insert(.down) }
        if buttons.contains(.dpadLeft) || leftStickX < -stickThreshold { held.insert(.left) }
        if buttons.contains(.dpadRight) || leftStickX > stickThreshold { held.insert(.right) }
        return held
    }
}
