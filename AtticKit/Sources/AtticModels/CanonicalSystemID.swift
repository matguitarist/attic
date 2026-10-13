/// A stable, internal identifier for a game system (e.g. "snes"), independent
/// of any particular library convention's own short-name for that system.
///
/// Batocera/RetroBat and ES-DE sometimes disagree on short names for the same
/// system (e.g. Genesis/Mega Drive is `megadrive` in Batocera, `genesis` in
/// ES-DE) — `CanonicalSystemID` is the one vocabulary everything above the
/// importer layer is written against. See `SystemTaxonomy` for the alias table.
public struct CanonicalSystemID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CanonicalSystemID: CustomStringConvertible {
    public var description: String { rawValue }
}

extension CanonicalSystemID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public extension CanonicalSystemID {
    static let nes = CanonicalSystemID("nes")
    static let snes = CanonicalSystemID("snes")
    static let genesis = CanonicalSystemID("genesis")
    static let psx = CanonicalSystemID("psx")
    static let gba = CanonicalSystemID("gba")

    // Sega
    static let mastersystem = CanonicalSystemID("mastersystem")
    static let gamegear = CanonicalSystemID("gamegear")
    static let segacd = CanonicalSystemID("segacd")
    static let saturn = CanonicalSystemID("saturn")
    static let dreamcast = CanonicalSystemID("dreamcast")
    static let sega32x = CanonicalSystemID("sega32x")

    // Atari
    static let atari2600 = CanonicalSystemID("atari2600")
    static let atari5200 = CanonicalSystemID("atari5200")
    static let atari7800 = CanonicalSystemID("atari7800")
    static let atarilynx = CanonicalSystemID("atarilynx")
    static let atarijaguar = CanonicalSystemID("atarijaguar")

    // NEC
    static let pcengine = CanonicalSystemID("pcengine")
    static let pcenginecd = CanonicalSystemID("pcenginecd")
    static let pcfx = CanonicalSystemID("pcfx")
    static let supergrafx = CanonicalSystemID("supergrafx")

    // Nintendo
    static let virtualboy = CanonicalSystemID("virtualboy")

    // Arcade
    static let neogeo = CanonicalSystemID("neogeo")
    static let cps1 = CanonicalSystemID("cps1")
    static let cps2 = CanonicalSystemID("cps2")
    static let cps3 = CanonicalSystemID("cps3")
    /// Sega / Namco / Nintendo's GameCube-based arcade board.
    static let triforce = CanonicalSystemID("triforce")
    static let gb = CanonicalSystemID("gb")
    static let gbc = CanonicalSystemID("gbc")
    static let n64 = CanonicalSystemID("n64")
    static let nds = CanonicalSystemID("nds")
    static let n3ds = CanonicalSystemID("n3ds")
    static let gamecube = CanonicalSystemID("gamecube")
    static let wii = CanonicalSystemID("wii")
    static let wiiu = CanonicalSystemID("wiiu")
    static let fds = CanonicalSystemID("fds")
    static let pokemini = CanonicalSystemID("pokemini")
    static let gameandwatch = CanonicalSystemID("gameandwatch")
    static let sg1000 = CanonicalSystemID("sg1000")
    static let naomi = CanonicalSystemID("naomi")
    static let atomiswave = CanonicalSystemID("atomiswave")
    static let naomi2 = CanonicalSystemID("naomi2")
    static let naomigd = CanonicalSystemID("naomigd")
    static let model2 = CanonicalSystemID("model2")
    static let stv = CanonicalSystemID("stv")
    static let gaelco = CanonicalSystemID("gaelco")
    static let n64dd = CanonicalSystemID("n64dd")
    static let satellaview = CanonicalSystemID("satellaview")
    static let sufami = CanonicalSystemID("sufami")
    static let model3 = CanonicalSystemID("model3")
    static let psp = CanonicalSystemID("psp")
    static let ps2 = CanonicalSystemID("ps2")
    static let ps3 = CanonicalSystemID("ps3")
    static let ps4 = CanonicalSystemID("ps4")
    static let psvita = CanonicalSystemID("psvita")
    static let scummvm = CanonicalSystemID("scummvm")
    static let doom = CanonicalSystemID("doom")
    static let quake = CanonicalSystemID("quake")
    static let easyrpg = CanonicalSystemID("easyrpg")
    static let x68000 = CanonicalSystemID("x68000")
    static let pc88 = CanonicalSystemID("pc88")
    static let pc98 = CanonicalSystemID("pc98")
    static let pico8 = CanonicalSystemID("pico8")
    static let tic80 = CanonicalSystemID("tic80")
    static let wasm4 = CanonicalSystemID("wasm4")
    static let arduboy = CanonicalSystemID("arduboy")
    static let vic20 = CanonicalSystemID("vic20")
    static let plus4 = CanonicalSystemID("plus4")
    static let c128 = CanonicalSystemID("c128")
    static let zx81 = CanonicalSystemID("zx81")
    static let macintosh = CanonicalSystemID("macintosh")
    static let xbox = CanonicalSystemID("xbox")
    static let msx = CanonicalSystemID("msx")
    static let dos = CanonicalSystemID("dos")
    static let wonderswan = CanonicalSystemID("wonderswan")
    static let wonderswancolor = CanonicalSystemID("wonderswancolor")
    static let ngp = CanonicalSystemID("ngp")
    static let ngpc = CanonicalSystemID("ngpc")
    static let neogeocd = CanonicalSystemID("neogeocd")
    static let atarist = CanonicalSystemID("atarist")
    static let atari800 = CanonicalSystemID("atari800")
    static let colecovision = CanonicalSystemID("colecovision")
    static let intellivision = CanonicalSystemID("intellivision")
    static let vectrex = CanonicalSystemID("vectrex")
    static let odyssey2 = CanonicalSystemID("odyssey2")
    static let channelf = CanonicalSystemID("channelf")
    static let c64 = CanonicalSystemID("c64")
    static let amiga = CanonicalSystemID("amiga")
    static let zxspectrum = CanonicalSystemID("zxspectrum")
    static let amstradcpc = CanonicalSystemID("amstradcpc")
    static let mame = CanonicalSystemID("mame")
    static let fbneo = CanonicalSystemID("fbneo")

    // Other
    static let threedo = CanonicalSystemID("3do")
    static let cdi = CanonicalSystemID("cdi")
}
