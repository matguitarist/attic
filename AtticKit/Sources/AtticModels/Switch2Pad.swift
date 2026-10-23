import Foundation

/// Nintendo's Switch 2 controllers over USB.
///
/// macOS has no support for them: plugged in, the Pro Controller shows up
/// as a HID device but sends nothing until it gets a start-up sequence on
/// a second, vendor-specific USB interface. After that it streams 64-byte
/// input reports on the HID interface, which `XInputPadState(switch2Report:)`
/// reads into the same state the wired Xbox pads produce.
///
/// The commands and report layout come from the community's reverse
/// engineering of the controller, as used by InputConfig
/// (github.com/ryleighnewman/InputConfig, MIT) after procon2-mac
/// (github.com/caqlayan/procon2-mac, MIT, © 2026 Arda Caglayan Ercan) and
/// SDL's SDL_hidapi_switch2.c.
public enum Switch2Pad {
    public static let vendorID = 0x057E
    /// The Pro Controller. The GameCube controller and Joy-Con 2 take the
    /// same start-up sequence but lay their reports out differently.
    public static let productIDs = [0x2069]
    /// The vendor interface the start-up sequence goes to, on its bulk
    /// OUT endpoint.
    public static let commandInterfaceNumber = 1

    /// Sent in order. Framing: command, 0x91, 0x00, sub-command, 0x00,
    /// payload length, 0x00, 0x00, then the payload.
    public static let startCommands: [[UInt8]] = [
        // Start reporting.
        [0x03, 0x91, 0x00, 0x0D, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
        [0x07, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
        [0x16, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
        // Player lights off.
        [0x09, 0x91, 0x00, 0x07, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        // Motion sensors on.
        [0x0C, 0x91, 0x00, 0x02, 0x00, 0x04, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00],
        [0x11, 0x91, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00],
        [0x0A, 0x91, 0x00, 0x08, 0x00, 0x14, 0x00, 0x00, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x35, 0x00, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        [0x0C, 0x91, 0x00, 0x04, 0x00, 0x04, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00],
        // Report format 0x05, the full 64-byte state.
        [0x03, 0x91, 0x00, 0x0A, 0x00, 0x04, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00],
        [0x10, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
        [0x01, 0x91, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x00],
        // InputConfig sends 0x03, 0x91, 0x00, 0x01 here too; to this
        // Pro Controller it's a reset: it drops off USB and comes back
        // unstarted, over and over.
        [0x0A, 0x91, 0x00, 0x02, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00],
        // Player light 1, so the pad shows it's connected.
        [0x09, 0x91, 0x00, 0x07, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    ]

    /// The sticks' 12-bit values: their usual center, and the distance
    /// from it to a full push. Pads differ a little; for moving through
    /// menus, which only asks whether a stick is pushed halfway, the usual
    /// values are close enough.
    static let stickCenter = 2048
    static let stickSpan = 1650
}

extension XInputPadState {
    /// A Switch 2 controller's report 0x05. Buttons are taken by position,
    /// as everywhere in Attic: Nintendo's B, at the bottom, is XInput's A.
    ///
    ///     [5] Y, X, B, A (bits 0–3), R (6), ZR (7)
    ///     [6] −, +, right stick, left stick, Home (bits 0–4)
    ///     [7] D-pad down, up, right, left (bits 0–3), L (6), ZL (7)
    ///     [11–13] left stick, [14–16] right stick: two 12-bit values each
    ///
    /// Returns `nil` for anything else the pad sends, such as replies to
    /// commands, so they never read as every button released.
    public init?(switch2Report report: [UInt8]) {
        guard report.count >= 63, report[0] == 0x05 else { return nil }
        let face = report[5], middle = report[6], left = report[7]
        func bit(_ byte: UInt8, _ index: Int) -> Bool { byte & (1 << index) != 0 }

        var buttons: XInputButtons = []
        if bit(face, 0) { buttons.insert(.x) }
        if bit(face, 1) { buttons.insert(.y) }
        if bit(face, 2) { buttons.insert(.a) }
        if bit(face, 3) { buttons.insert(.b) }
        if bit(face, 6) { buttons.insert(.rightShoulder) }
        if bit(middle, 0) { buttons.insert(.back) }
        if bit(middle, 1) { buttons.insert(.start) }
        if bit(middle, 2) { buttons.insert(.rightThumb) }
        if bit(middle, 3) { buttons.insert(.leftThumb) }
        if bit(middle, 4) { buttons.insert(.guide) }
        if bit(left, 0) { buttons.insert(.dpadDown) }
        if bit(left, 1) { buttons.insert(.dpadUp) }
        if bit(left, 2) { buttons.insert(.dpadRight) }
        if bit(left, 3) { buttons.insert(.dpadLeft) }
        if bit(left, 6) { buttons.insert(.leftShoulder) }

        let rawX = Int(report[11]) | Int(report[12] & 0x0F) << 8
        let rawY = Int(report[12] >> 4) | Int(report[13]) << 4
        func axis(_ raw: Int) -> Int16 {
            let scaled = (raw - Switch2Pad.stickCenter) * Int(Int16.max) / Switch2Pad.stickSpan
            return Int16(clamping: scaled)
        }
        // ZL and ZR are buttons, not analog triggers.
        self.init(buttons: buttons, leftStickX: axis(rawX), leftStickY: axis(rawY),
                  leftTrigger: bit(left, 7) ? 255 : 0, rightTrigger: bit(face, 7) ? 255 : 0)
    }
}
