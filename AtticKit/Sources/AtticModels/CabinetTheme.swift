import Foundation

/// How Cabinet Mode looks: its layout, colors, type, art and what the
/// focused game shows. Every value a theme can change lives here, so a
/// theme is one JSON file (`theme.json`) and a theme editor only needs to
/// edit this struct.
///
/// A theme file can name a `base` theme and set only what differs:
///
///     { "name": "Purple Arcade", "base": "arcade",
///       "palette": { "accent": "#B04CFF" } }
public struct CabinetTheme: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var author: String?
    public var layout: Layout
    public var palette: Palette
    public var typography: Typography
    public var backdrop: Backdrop
    public var tiles: Tiles
    public var details: Details
    public var header: Header
    public var menu: Menu
    public var systems: Systems
    public var showsHints: Bool

    public enum Layout: String, Codable, CaseIterable, Sendable {
        /// A row of big covers, the focused one's details below (Showcase).
        case carousel
        /// A grid of covers beside a details panel (Steam's Big Picture).
        case grid
        /// A vertical wheel of logos beside a screen playing the focused
        /// game's video (CoinOps, HyperSpin).
        case wheel
        /// A list of titles beside the focused game's art and details
        /// (EmulationStation's gamelist). The art is the tiles' `art`.
        case list
        /// The focused game's art filling the screen, its details over it
        /// at the top left, a row of wide cards along the bottom (Apple TV).
        case hero
    }

    public struct Palette: Codable, Hashable, Sendable {
        /// Behind everything, under the backdrop art.
        public var background: ThemeColor
        /// Panels and cards.
        public var surface: ThemeColor
        /// Focus, selection and highlights.
        public var accent: ThemeColor
        public var text: ThemeColor
        public var secondaryText: ThemeColor
        public var favorite: ThemeColor
    }

    public struct Typography: Codable, Hashable, Sendable {
        public enum Design: String, Codable, CaseIterable, Sendable {
            case standard, rounded, serif, monospaced
        }
        /// Used when `fontName` is unset or not installed.
        public var design: Design
        /// A font family's name, like "Avenir Next".
        public var fontName: String?
        /// The focused game's title, in points.
        public var titleSize: Double
        /// Everything else is sized from this.
        public var bodySize: Double
        /// Uppercases section names and the title, arcade style.
        public var uppercase: Bool
    }

    public struct Backdrop: Codable, Hashable, Sendable {
        public enum Source: String, Codable, CaseIterable, Sendable {
            /// Only the background color (and `image`).
            case none
            case cover, screenshot, fanart
        }
        /// The focused game's art behind everything. Fan art falls back to
        /// the screenshot, then the cover.
        public var source: Source
        /// In points; 0 keeps the art sharp.
        public var blur: Double
        /// How much the art is darkened, 0 to 1.
        public var dim: Double
        /// A picture in the theme's folder, drawn under the game's art.
        public var image: String?
        /// The art fades into the background color toward the bottom and
        /// the leading edge, so text over it stays readable with no blur.
        public var fade: Bool = false
        /// After a moment on a game, its video plays where its art is, as
        /// trailers do on the Apple TV. Settings › Cabinet Mode's video
        /// switch still decides.
        public var playsVideo: Bool = false
    }

    public struct Tiles: Codable, Hashable, Sendable {
        public enum Art: String, Codable, CaseIterable, Sendable {
            /// The 2D box art.
            case cover
            /// A rendered 3D box.
            case box3D
            case screenshot, logo
            /// Wide art for wide cards, else the screenshot, else the cover.
            case fanart
        }
        /// What each game's tile shows. A 3D box falls back to the cover,
        /// a logo to the title.
        public var art: Art
        /// Of the shelf's height (the room between the header and the
        /// hints): carousel covers and grid tiles. In the wheel, of one
        /// entry's height.
        public var size: Double
        public var spacing: Double
        public var cornerRadius: Double
        /// Draws a card behind tile art.
        public var showsBackground: Bool
        /// The focused tile's size against the others'.
        public var focusScale: Double
        /// The other tiles' opacity, 0 to 1.
        public var unfocusedOpacity: Double
        /// A ring of the accent color around the focused tile.
        public var focusRing: Bool
        /// The accent color glowing around the focused tile.
        public var focusGlow: Bool
        public var showsTitles: Bool
    }

    public struct Details: Codable, Hashable, Sendable {
        public enum Media: String, Codable, CaseIterable, Sendable {
            case none, cover, box3D, screenshot, fanart
        }
        public enum TitlePosition: String, Codable, CaseIterable, Sendable {
            case top, bottom
        }
        public enum Side: String, Codable, CaseIterable, Sendable {
            case leading, trailing
        }
        /// The picture in the details: a video plays over it after a
        /// moment when `playsVideo` is on.
        public var media: Media
        public var playsVideo: Bool
        /// The game's logo in place of its title, when it has one.
        public var showsLogo: Bool
        /// Where a side panel puts the title or logo: under the picture,
        /// or at the panel's foot.
        public var titlePosition: TitlePosition = .top
        /// Which side the grid's details panel and the game page's art and
        /// facts take.
        public var side: Side = .leading
        public var showsMetadata: Bool
        public var showsDescription: Bool
        public var descriptionLines: Int
    }

    public struct Header: Codable, Hashable, Sendable {
        /// Systems and collections as their logos, else as names.
        public var showsLogos: Bool
        public var showsClock: Bool
        /// How many games the section has.
        public var showsGameCount: Bool
    }

    /// The level before the games: a strip of systems, collections and
    /// shortcuts, the focused one's picture and facts above it.
    public struct Systems: Codable, Hashable, Sendable {
        /// Opens on the systems; else straight on the games, sections in
        /// the header.
        public var isEnabled: Bool
        /// How many games, played, favorites and play time.
        public var showsStats: Bool
        /// A system's or collection's own video, after a moment, where its
        /// picture is.
        public var playsVideo: Bool
        /// A folder in the theme holding each system's picture, named
        /// after it (snes.png, megadrive.jpg, arcade.png). Without one,
        /// the system's covers fan out instead.
        public var artFolder: String
    }

    /// The menu Start opens: theme, interface, controller, library.
    public struct Menu: Codable, Hashable, Sendable {
        public enum Position: String, Codable, CaseIterable, Sendable {
            case center, leading, trailing
        }
        /// In the middle, or a full-height panel along a side.
        public var position: Position
        /// In points.
        public var width: Double
        public var cornerRadius: Double
        /// How much the screen behind darkens, 0 to 1.
        public var dim: Double
    }
}

/// A color written as "#RRGGBB" or "#RRGGBBAA" in a theme.
public struct ThemeColor: Codable, Hashable, Sendable, CustomStringConvertible {
    public var red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        func channel(_ shift: UInt64) -> Double { Double(rgba >> shift & 0xFF) / 255 }
        self.init(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    public var hex: String {
        func byte(_ value: Double) -> String { String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded())) }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 1 ? byte(alpha) : "")
    }

    public var description: String { hex }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = ThemeColor(hex: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "“\(text)” isn't a #RRGGBB or #RRGGBBAA color")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

// MARK: - Reading and writing

extension CabinetTheme {
    /// Reads a theme file: its values over those of its `base` (a built-in
    /// theme's id), else over Showcase's, so a file needs only what differs
    /// and older files keep working as themes gain settings.
    public static func decode(_ data: Data, id: String) throws -> CabinetTheme {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A theme is a JSON object"))
        }
        let base = (object["base"] as? String).flatMap(builtIn(id:)) ?? .showcase
        var merged = merging(object, over: try base.jsonObject())
        merged["id"] = id
        merged["base"] = nil
        return try JSONDecoder().decode(CabinetTheme.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    /// The theme with some of its values replaced, written as in a theme
    /// file: `["palette": ["accent": "#B04CFF"], "layout": "grid"]`.
    public func applying(_ overrides: [String: Any]) throws -> CabinetTheme {
        guard !overrides.isEmpty else { return self }
        var merged = Self.merging(overrides, over: try jsonObject())
        merged["id"] = id
        return try JSONDecoder().decode(CabinetTheme.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    /// The theme as a file to edit: every value, keys sorted.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    private func jsonObject() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] ?? [:]
    }

    /// Nested objects merge key by key; anything else replaces.
    static func merging(_ top: [String: Any], over bottom: [String: Any]) -> [String: Any] {
        bottom.merging(top) { below, above in
            if let below = below as? [String: Any], let above = above as? [String: Any] {
                return merging(above, over: below)
            }
            return above
        }
    }
}

// MARK: - Built-in themes

extension CabinetTheme {
    public static let builtIns: [CabinetTheme] = [.showcase, .appleTV, .bigPicture, .arcade, .classic]

    public static func builtIn(id: String) -> CabinetTheme? {
        builtIns.first { $0.id == id }
    }

    /// Big covers in a row over the focused game's blurred cover.
    public static let showcase = CabinetTheme(
        id: "showcase",
        name: "Showcase",
        author: "Attic",
        layout: .carousel,
        palette: Palette(
            background: ThemeColor(hex: "#000000")!,
            surface: ThemeColor(hex: "#FFFFFF1A")!,
            accent: ThemeColor(hex: "#FFFFFF")!,
            text: ThemeColor(hex: "#FFFFFF")!,
            secondaryText: ThemeColor(hex: "#FFFFFF99")!,
            favorite: ThemeColor(hex: "#FFD60A")!
        ),
        typography: Typography(design: .standard, titleSize: 44, bodySize: 20, uppercase: false),
        backdrop: Backdrop(source: .cover, blur: 60, dim: 0.6),
        tiles: Tiles(art: .cover, size: 1, spacing: 36, cornerRadius: 0, showsBackground: false,
                     focusScale: 1.38, unfocusedOpacity: 0.45, focusRing: false, focusGlow: false, showsTitles: false),
        details: Details(media: .none, playsVideo: false, showsLogo: false, showsMetadata: true, showsDescription: true, descriptionLines: 3),
        header: Header(showsLogos: true, showsClock: false, showsGameCount: false),
        menu: Menu(position: .center, width: 640, cornerRadius: 28, dim: 0.55),
        systems: Systems(isEnabled: true, showsStats: true, playsVideo: true, artFolder: "systems"),
        showsHints: true
    )

    /// A grid of covers beside the focused game's video and details, over
    /// its fan art, like Steam's Big Picture.
    public static let bigPicture = CabinetTheme(
        id: "big-picture",
        name: "Big Picture",
        author: "Attic",
        layout: .grid,
        palette: Palette(
            background: ThemeColor(hex: "#0E141B")!,
            surface: ThemeColor(hex: "#1B2838E6")!,
            accent: ThemeColor(hex: "#1A9FFF")!,
            text: ThemeColor(hex: "#FFFFFF")!,
            secondaryText: ThemeColor(hex: "#B8C4D0")!,
            favorite: ThemeColor(hex: "#FFC82C")!
        ),
        typography: Typography(design: .standard, fontName: "Avenir Next", titleSize: 34, bodySize: 17, uppercase: false),
        backdrop: Backdrop(source: .fanart, blur: 24, dim: 0.72),
        tiles: Tiles(art: .cover, size: 0.44, spacing: 22, cornerRadius: 8, showsBackground: true,
                     focusScale: 1.06, unfocusedOpacity: 0.85, focusRing: true, focusGlow: true, showsTitles: false),
        details: Details(media: .screenshot, playsVideo: true, showsLogo: true, titlePosition: .bottom, showsMetadata: true,
                         showsDescription: true, descriptionLines: 6),
        header: Header(showsLogos: false, showsClock: true, showsGameCount: true),
        menu: Menu(position: .leading, width: 560, cornerRadius: 0, dim: 0.5),
        systems: Systems(isEnabled: true, showsStats: true, playsVideo: true, artFolder: "systems"),
        showsHints: true
    )

    /// A wheel of logos beside a screen playing the focused game's video,
    /// like CoinOps.
    public static let arcade = CabinetTheme(
        id: "arcade",
        name: "Arcade",
        author: "Attic",
        layout: .wheel,
        palette: Palette(
            background: ThemeColor(hex: "#07020F")!,
            surface: ThemeColor(hex: "#1A0B2ECC")!,
            accent: ThemeColor(hex: "#FF2E88")!,
            text: ThemeColor(hex: "#FFFFFF")!,
            secondaryText: ThemeColor(hex: "#C9B8FF")!,
            favorite: ThemeColor(hex: "#FFE600")!
        ),
        typography: Typography(design: .rounded, titleSize: 30, bodySize: 18, uppercase: true),
        backdrop: Backdrop(source: .screenshot, blur: 40, dim: 0.75),
        tiles: Tiles(art: .logo, size: 0.8, spacing: 6, cornerRadius: 12, showsBackground: false,
                     focusScale: 1.35, unfocusedOpacity: 0.4, focusRing: false, focusGlow: true, showsTitles: true),
        details: Details(media: .screenshot, playsVideo: true, showsLogo: false, showsMetadata: true, showsDescription: false, descriptionLines: 2),
        header: Header(showsLogos: true, showsClock: false, showsGameCount: true),
        menu: Menu(position: .center, width: 600, cornerRadius: 12, dim: 0.7),
        systems: Systems(isEnabled: true, showsStats: true, playsVideo: true, artFolder: "systems"),
        showsHints: true
    )

    /// A list of titles beside the focused game's 3D box and details, like
    /// EmulationStation.
    public static let classic = CabinetTheme(
        id: "classic",
        name: "Classic",
        author: "Attic",
        layout: .list,
        palette: Palette(
            background: ThemeColor(hex: "#15171C")!,
            surface: ThemeColor(hex: "#262A33E6")!,
            accent: ThemeColor(hex: "#E8A33D")!,
            text: ThemeColor(hex: "#FFFFFF")!,
            secondaryText: ThemeColor(hex: "#A9B0BC")!,
            favorite: ThemeColor(hex: "#FFD60A")!
        ),
        typography: Typography(design: .standard, titleSize: 32, bodySize: 18, uppercase: false),
        backdrop: Backdrop(source: .fanart, blur: 30, dim: 0.82),
        tiles: Tiles(art: .box3D, size: 1, spacing: 2, cornerRadius: 8, showsBackground: false,
                     focusScale: 1.2, unfocusedOpacity: 0.6, focusRing: false, focusGlow: false, showsTitles: false),
        details: Details(media: .screenshot, playsVideo: true, showsLogo: false, showsMetadata: true, showsDescription: true, descriptionLines: 8),
        header: Header(showsLogos: true, showsClock: true, showsGameCount: true),
        menu: Menu(position: .center, width: 600, cornerRadius: 14, dim: 0.6),
        systems: Systems(isEnabled: true, showsStats: true, playsVideo: true, artFolder: "systems"),
        showsHints: true
    )

    /// The focused game's fan art filling the screen, sharp and fading to
    /// black, over a row of wide cards that lift when focused, like the
    /// Apple TV's Home screen.
    public static let appleTV = CabinetTheme(
        id: "apple-tv",
        name: "Apple TV",
        author: "Attic",
        layout: .hero,
        palette: Palette(
            background: ThemeColor(hex: "#000000")!,
            surface: ThemeColor(hex: "#FFFFFF24")!,
            accent: ThemeColor(hex: "#FFFFFF")!,
            text: ThemeColor(hex: "#FFFFFF")!,
            secondaryText: ThemeColor(hex: "#FFFFFFA6")!,
            favorite: ThemeColor(hex: "#FFD60A")!
        ),
        typography: Typography(design: .standard, titleSize: 52, bodySize: 21, uppercase: false),
        backdrop: Backdrop(source: .fanart, blur: 0, dim: 0.05, fade: true, playsVideo: true),
        tiles: Tiles(art: .fanart, size: 0.24, spacing: 44, cornerRadius: 16, showsBackground: false,
                     focusScale: 1.1, unfocusedOpacity: 0.85, focusRing: false, focusGlow: false, showsTitles: false),
        details: Details(media: .none, playsVideo: false, showsLogo: true, showsMetadata: true,
                         showsDescription: true, descriptionLines: 3),
        header: Header(showsLogos: false, showsClock: true, showsGameCount: false),
        menu: Menu(position: .center, width: 680, cornerRadius: 30, dim: 0.5),
        systems: Systems(isEnabled: true, showsStats: true, playsVideo: true, artFolder: "systems"),
        showsHints: true
    )
}
