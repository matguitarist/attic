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
    static let model1 = CanonicalSystemID("model1")
    static let hikaru = CanonicalSystemID("hikaru")
    static let amigacd32 = CanonicalSystemID("amigacd32")
    static let cdtv = CanonicalSystemID("cdtv")
    static let gx4000 = CanonicalSystemID("gx4000")
    static let megaduck = CanonicalSystemID("megaduck")
    static let moto = CanonicalSystemID("moto")
    static let spectravideo = CanonicalSystemID("spectravideo")
    static let supervision = CanonicalSystemID("supervision")
    static let x1 = CanonicalSystemID("x1")
    static let segapico = CanonicalSystemID("segapico")
    static let pet = CanonicalSystemID("pet")
    static let model2 = CanonicalSystemID("model2")
    static let stv = CanonicalSystemID("stv")
    static let gaelco = CanonicalSystemID("gaelco")
    static let namco2x6 = CanonicalSystemID("namco2x6")
    static let namco22 = CanonicalSystemID("namco22")
    static let neogeo64 = CanonicalSystemID("neogeo64")
    static let zinc = CanonicalSystemID("zinc")
    static let pspminis = CanonicalSystemID("pspminis")
    static let wiiware = CanonicalSystemID("wiiware")
    static let dsiware = CanonicalSystemID("dsiware")
    static let apfm1000 = CanonicalSystemID("apfm1000")
    static let socrates = CanonicalSystemID("socrates")
    static let pv2000 = CanonicalSystemID("pv2000")
    static let tutor = CanonicalSystemID("tutor")
    static let aquarius = CanonicalSystemID("aquarius")
    static let vg5k = CanonicalSystemID("vg5k")
    static let p2000t = CanonicalSystemID("p2000t")
    static let cannonball = CanonicalSystemID("cannonball")
    static let cavestory = CanonicalSystemID("cavestory")
    static let dinothawr = CanonicalSystemID("dinothawr")
    static let ecwolf = CanonicalSystemID("ecwolf")
    static let reminiscence = CanonicalSystemID("reminiscence")
    static let doom3 = CanonicalSystemID("doom3")
    static let j2me = CanonicalSystemID("j2me")
    static let xbox360 = CanonicalSystemID("xbox360")
    static let xbla = CanonicalSystemID("xbla")
    static let chihiro = CanonicalSystemID("chihiro")
    static let devilutionx = CanonicalSystemID("devilutionx")
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
    /// Mac games installed through Steam, played through it.
    static let steam = CanonicalSystemID("steam")
    /// Native Mac games and source ports: apps and scripts, run as they are.
    static let ports = CanonicalSystemID("ports")
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

    // Added from Batocera's and RetroBat's systems.
    static let `switch` = CanonicalSystemID("switch")
    static let sgb = CanonicalSystemID("sgb")
    static let advision = CanonicalSystemID("advision")
    static let arcadia = CanonicalSystemID("arcadia")
    static let astrocade = CanonicalSystemID("astrocade")
    static let crvision = CanonicalSystemID("crvision")
    static let cassettevision = CanonicalSystemID("cassettevision")
    static let scv = CanonicalSystemID("scv")
    static let vc4000 = CanonicalSystemID("vc4000")
    static let pv1000 = CanonicalSystemID("pv1000")
    static let supracan = CanonicalSystemID("supracan")
    static let vsmile = CanonicalSystemID("vsmile")
    static let loopy = CanonicalSystemID("loopy")
    static let uzebox = CanonicalSystemID("uzebox")
    static let lowresnx = CanonicalSystemID("lowresnx")
    static let lutro = CanonicalSystemID("lutro")
    static let vircon32 = CanonicalSystemID("vircon32")
    static let gamate = CanonicalSystemID("gamate")
    static let gamecom = CanonicalSystemID("gamecom")
    static let gmaster = CanonicalSystemID("gmaster")
    static let gamepock = CanonicalSystemID("gamepock")
    static let lcdgames = CanonicalSystemID("lcdgames")
    static let apple2 = CanonicalSystemID("apple2")
    static let apple2gs = CanonicalSystemID("apple2gs")
    static let bbcmicro = CanonicalSystemID("bbcmicro")
    static let electron = CanonicalSystemID("electron")
    static let atom = CanonicalSystemID("atom")
    static let archimedes = CanonicalSystemID("archimedes")
    static let coco = CanonicalSystemID("coco")
    static let dragon32 = CanonicalSystemID("dragon32")
    static let ti99 = CanonicalSystemID("ti99")
    static let oricatmos = CanonicalSystemID("oricatmos")
    static let samcoupe = CanonicalSystemID("samcoupe")
    static let fm7 = CanonicalSystemID("fm7")
    static let fmtowns = CanonicalSystemID("fmtowns")
    static let camplynx = CanonicalSystemID("camplynx")
    static let adam = CanonicalSystemID("adam")
    static let bk = CanonicalSystemID("bk")

    // Other
    static let threedo = CanonicalSystemID("3do")
    static let cdi = CanonicalSystemID("cdi")
}
