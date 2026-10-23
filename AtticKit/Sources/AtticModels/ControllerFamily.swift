import Foundation

/// The kind of controller, for drawing its buttons as they're printed on
/// it: A on an Xbox pad, Cross on a PlayStation one, B on a Switch one —
/// all the same `bottom` button.
public enum ControllerFamily: String, Sendable, Codable, CaseIterable, Hashable {
    case xbox
    case playStation
    case nintendo
    case eightBitDo
    case stadia
    /// No controller: the keys that do the same in Cabinet Mode.
    case keyboard

    /// Guessed from what the controller calls itself. Anything unknown
    /// gets Xbox's buttons, the layout most pads copy.
    public static func detect(name: String?, category: String? = nil) -> ControllerFamily {
        let text = [name, category].compactMap { $0?.lowercased() }.joined(separator: " ")
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        // 8BitDo first: their pads often call themselves "Pro Controller"
        // or "Xbox" too, depending on the mode they're in.
        if has("8bitdo") { return .eightBitDo }
        if has("stadia") { return .stadia }
        if has("dualsense", "dualshock", "playstation", "ps4", "ps5", "sony") { return .playStation }
        // Sony's own name for the DualShock 4 over USB.
        if text.hasPrefix("wireless controller") { return .playStation }
        if has("nintendo", "switch", "joy-con", "pro controller", "gamecube") { return .nintendo }
        return .xbox
    }

    /// An SF Symbol for the controller itself. Only PlayStation and Xbox
    /// have their own; everything else is a generic controller.
    public var symbol: String {
        switch self {
        case .playStation: "playstation.logo"
        case .xbox: "xbox.logo"
        case .keyboard: "keyboard"
        case .nintendo, .eightBitDo, .stadia: "gamecontroller.fill"
        }
    }

    /// How `physical` looks on this controller. `layout` only matters for
    /// the keyboard, where Return confirms and Escape goes back whichever
    /// face button does that on a pad.
    public func glyph(for physical: PhysicalButton, layout: ButtonLayout = .classic) -> ButtonGlyph {
        switch self {
        case .keyboard: Self.keyboardGlyph(for: physical, layout: layout)
        case .xbox, .stadia, .playStation, .nintendo, .eightBitDo: .symbol(padSymbol(for: physical))
        }
    }

    private func padSymbol(for physical: PhysicalButton) -> String {
        switch (self, physical) {
        case (.playStation, .bottom): "xmark.circle.fill"
        case (.playStation, .right): "circle.circle.fill"
        case (.playStation, .left): "square.circle.fill"
        case (.playStation, .top): "triangle.circle.fill"
        // Nintendo prints A and B, X and Y the other way round.
        case (.nintendo, .bottom), (.eightBitDo, .bottom): "b.circle.fill"
        case (.nintendo, .right), (.eightBitDo, .right): "a.circle.fill"
        case (.nintendo, .left), (.eightBitDo, .left): "y.circle.fill"
        case (.nintendo, .top), (.eightBitDo, .top): "x.circle.fill"
        case (_, .bottom): "a.circle.fill"
        case (_, .right): "b.circle.fill"
        case (_, .left): "x.circle.fill"
        case (_, .top): "y.circle.fill"

        case (.xbox, .l1): "lb.rectangle.roundedbottom.fill"
        case (.xbox, .r1): "rb.rectangle.roundedbottom.fill"
        case (.xbox, .l2): "lt.rectangle.roundedtop.fill"
        case (.xbox, .r2): "rt.rectangle.roundedtop.fill"
        case (.nintendo, .l1), (.eightBitDo, .l1): "l.rectangle.roundedbottom.fill"
        case (.nintendo, .r1), (.eightBitDo, .r1): "r.rectangle.roundedbottom.fill"
        case (.nintendo, .l2): "zl.rectangle.roundedtop.fill"
        case (.nintendo, .r2): "zr.rectangle.roundedtop.fill"
        case (_, .l1): "l1.rectangle.roundedbottom.fill"
        case (_, .r1): "r1.rectangle.roundedbottom.fill"
        case (_, .l2): "l2.rectangle.roundedtop.fill"
        case (_, .r2): "r2.rectangle.roundedtop.fill"

        case (.xbox, .select): "rectangle.on.rectangle.circle.fill"
        case (.playStation, .select): "square.and.arrow.up.circle.fill"
        case (.stadia, .select): "ellipsis.circle.fill"
        case (_, .select): "minus.circle.fill"
        case (.nintendo, .start), (.eightBitDo, .start): "plus.circle.fill"
        case (_, .start): "line.3.horizontal.circle.fill"

        case (_, .l3): "l.joystick.press.down.fill"
        case (_, .r3): "r.joystick.press.down.fill"
        case (_, .dpadUp): "dpad.up.filled"
        case (_, .dpadDown): "dpad.down.filled"
        case (_, .dpadLeft): "dpad.left.filled"
        case (_, .dpadRight): "dpad.right.filled"
        }
    }

    /// The Cabinet Mode key that does what `physical` does on a pad.
    private static func keyboardGlyph(for physical: PhysicalButton, layout: ButtonLayout) -> ButtonGlyph {
        let confirm: PhysicalButton = layout == .classic ? .bottom : .right
        switch physical {
        case confirm: return .symbol("return")
        case .bottom, .right: return .symbol("escape")
        case .left: return .symbol("space")
        case .top: return .key("F")
        case .select: return .key("/")
        case .start: return .key("M")
        case .r3: return .key("R")
        case .l2: return .key("[")
        case .r2: return .key("]")
        case .l1, .r1: return .key("Tab")
        case .l3: return .key("—")
        case .dpadUp: return .symbol("arrowtriangle.up.square.fill")
        case .dpadDown: return .symbol("arrowtriangle.down.square.fill")
        case .dpadLeft: return .symbol("arrowtriangle.left.square.fill")
        case .dpadRight: return .symbol("arrowtriangle.right.square.fill")
        }
    }
}

/// A button as drawn in on-screen hints: an SF Symbol, or a keyboard key's
/// label, drawn as a keycap.
public enum ButtonGlyph: Sendable, Hashable {
    case symbol(String)
    case key(String)
}
