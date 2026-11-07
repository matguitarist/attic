import CoreGraphics

/// Corner radii. The first three are the scale every Mac app of mine shares:
/// small boxes and swatches use `control`, banners `banner`, cards on a page `card`.
enum Radius {
    static let control: CGFloat = 8
    static let banner: CGFloat = 12
    static let card: CGFloat = 16

    // Attic's own.
    /// Box art and the game header media.
    static let cover: CGFloat = 10
    /// A short monospaced value inline in text, like a file name.
    static let chip: CGFloat = 4
    /// A keyboard key drawn in a button hint.
    static let keycap: CGFloat = 5
}

/// The full-screen Cabinet is seen from across the room, so its corners
/// follow its own sizes rather than the library's. Theme radii come from
/// `CabinetTheme`; these are the fixed pieces around them.
enum CabinetRadius {
    /// The shelf plank under a row of boxes.
    static let plank: CGFloat = 3
    /// The bezel art around the game's screen.
    static let bezel: CGFloat = 4
    /// The glowing tube in the arcade layout.
    static let tube: CGFloat = 6
    /// The monitor frame around a game without bezel art.
    static let monitor: CGFloat = 8
    /// A focused row in a list, and a key on the search keyboard.
    static let button: CGFloat = 10
    /// The search field.
    static let field: CGFloat = 12
    /// The panel beside a game's page.
    static let panel: CGFloat = 20
    /// The screen inside the monitor frame.
    static let screen: CGFloat = 22
    /// The search panel.
    static let sheet: CGFloat = 24
    /// The big letter shown while jumping through the alphabet.
    static let jump: CGFloat = 32
}
