import Foundation
import Testing
@testable import AtticEmulation

@Suite("Arcade set verification")
struct ArcadeVerifierTests {
    private let root: URL
    private let dats: URL
    private let roms: URL
    private let bios: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ArcadeVerifierTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        dats = root.appending(path: "DATs", directoryHint: .isDirectory)
        roms = root.appending(path: "ROMs/mame", directoryHint: .isDirectory)
        bios = root.appending(path: "BIOS", directoryHint: .isDirectory)
        for folder in [dats, roms, bios] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    private func crc(_ data: Data) -> String { String(format: "%08x", CoreUpdateChecker.crc32(of: data)) }
    private func chip(_ byte: UInt8) -> Data { Data(repeating: byte, count: 1024) }

    /// A zip of `files` (name → data) at `url`.
    private func zip(_ url: URL, _ files: [String: Data]) throws {
        let work = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: work.appending(path: name)) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-j", url.path] + files.keys.sorted().map { work.appending(path: $0).path }
        try process.run()
        process.waitUntilExit()
    }

    /// MAME's -listxml, much shortened: a game, its clone, and a GD-ROM
    /// game with a disc image.
    private func writeMAMEList() throws {
        let xml = """
        <?xml version="1.0"?>
        <mame build="0.289 (mame0289)">
          <machine name="game" romof="board">
            <description>A Game (World, set 1)</description>
            <rom name="g1.bin" size="1024" crc="\(crc(chip(1)))"/>
            <rom name="g2.bin" size="1024" crc="\(crc(chip(2)))"/>
            <rom name="bios.bin" merge="bios.bin" bios="v1" size="1024" crc="\(crc(chip(9)))"/>
            <rom name="unknown.bin" size="1024" status="nodump"/>
          </machine>
          <machine name="gamej" cloneof="game" romof="game">
            <description>A Game (Japan)</description>
            <rom name="g1.bin" merge="g1.bin" size="1024" crc="\(crc(chip(1)))"/>
            <rom name="g2j.bin" size="1024" crc="\(crc(chip(3)))"/>
          </machine>
          <machine name="gdgame" romof="board">
            <description>A GD-ROM Game</description>
            <rom name="pic.pic" size="1024" crc="\(crc(chip(4)))"/>
            <disk name="gdl-0001" sha1="\(String(repeating: "ab", count: 20))"/>
          </machine>
          <machine name="board" isbios="yes">
            <description>The Board BIOS</description>
          </machine>
        </mame>
        """
        try Data(xml.utf8).write(to: dats.appending(path: "mame.xml"))
    }

    private func load(_ wanted: Set<String>) -> ArcadeVerifier {
        ArcadeVerifier.load(from: dats, wanted: wanted, cacheDirectory: root.appending(path: "cache"))
    }

    @Test func aCompleteSetIsVerified() throws {
        try writeMAMEList()
        try zip(roms.appending(path: "game.zip"), ["g1.bin": chip(1), "g2.bin": chip(2)])
        let check = load(["game"]).check(roms.appending(path: "game.zip"), preferring: .mame, biosDirectory: bios)
        #expect(check?.verdict == .verified)
        #expect(check?.name == "A Game")
    }

    @Test func missingAndWrongChipsAreTold() throws {
        try writeMAMEList()
        try zip(roms.appending(path: "game.zip"), ["g1.bin": chip(7)])
        let check = load(["game"]).check(roms.appending(path: "game.zip"), preferring: .mame, biosDirectory: bios)
        #expect(check?.verdict == .differs)
        #expect(check?.detail?.contains("MAME 0.289") == true)
        // The CRC the chip should have, and the one it has.
        #expect(check?.detail?.contains(crc(chip(1)).lowercased()) == true)
        #expect(check?.detail?.contains(crc(chip(7)).lowercased()) == true)

        try FileManager.default.removeItem(at: roms.appending(path: "game.zip"))
        try zip(roms.appending(path: "game.zip"), ["g1.bin": chip(1)])
        #expect(load(["game"]).check(roms.appending(path: "game.zip"), preferring: .mame, biosDirectory: bios)?.verdict == .incomplete)
    }

    @Test func aCloneTakesItsParentsChips() throws {
        try writeMAMEList()
        try zip(roms.appending(path: "game.zip"), ["g1.bin": chip(1), "g2.bin": chip(2)])
        try zip(roms.appending(path: "gamej.zip"), ["g2j.bin": chip(3)])
        let verifier = load(["game", "gamej"])
        #expect(verifier.check(roms.appending(path: "gamej.zip"), preferring: .mame, biosDirectory: bios)?.verdict == .verified)
        // Without its parent, it lacks g1.bin.
        try FileManager.default.removeItem(at: roms.appending(path: "game.zip"))
        #expect(verifier.check(roms.appending(path: "gamej.zip"), preferring: .mame, biosDirectory: bios)?.verdict == .incomplete)
    }

    @Test func aDiscImageIsCheckedByItsHeader() throws {
        try writeMAMEList()
        try zip(roms.appending(path: "gdgame.zip"), ["pic.pic": chip(4)])
        let verifier = load(["gdgame"])
        #expect(verifier.check(roms.appending(path: "gdgame.zip"), preferring: .mame, biosDirectory: bios)?.detail?.contains("gdl-0001.chd") == true)

        // A CHD v5 header, with the disc's SHA-1 at byte 84.
        var header = Data("MComprHD".utf8) + Data([0, 0, 0, 124, 0, 0, 0, 5]) + Data(count: 68)
        header += Data(repeating: 0xab, count: 20) + Data(count: 20)
        let folder = roms.appending(path: "gdgame", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try header.write(to: folder.appending(path: "gdl-0001.chd"))
        #expect(verifier.check(roms.appending(path: "gdgame.zip"), preferring: .mame, biosDirectory: bios)?.verdict == .verified)

        header.replaceSubrange(84..<104, with: Data(repeating: 0xcd, count: 20))
        try header.write(to: folder.appending(path: "gdl-0001.chd"))
        #expect(verifier.check(roms.appending(path: "gdgame.zip"), preferring: .mame, biosDirectory: bios)?.verdict == .differs)
    }

    @Test func anUnknownSetAndNoDAT() throws {
        try writeMAMEList()
        try zip(roms.appending(path: "other.zip"), ["x.bin": chip(5)])
        #expect(load(["other"]).check(roms.appending(path: "other.zip"), preferring: .mame, biosDirectory: bios)?.verdict == .unknown)
        #expect(ArcadeVerifier.none.check(roms.appending(path: "other.zip"), preferring: .mame, biosDirectory: bios) == nil)
    }

    /// FinalBurn Neo lists each of a board's BIOS versions in every game:
    /// any one of them is enough.
    @Test func oneBIOSVersionIsEnough() throws {
        var games = ""
        for index in 0..<ArcadeVerifier.biosSharing {
            games += """
              <game name="ng\(index)" romof="neogeo">
                <description>Neo Game \(index)</description>
                <rom name="p\(index).bin" size="1024" crc="\(crc(chip(UInt8(100 + index))))"/>
                <rom name="sp-s2.sp1" merge="sp-s2.sp1" size="1024" crc="\(crc(chip(10)))"/>
                <rom name="uni-bios.rom" merge="uni-bios.rom" size="1024" crc="\(crc(chip(11)))"/>
              </game>

            """
        }
        let dat = """
        <?xml version="1.0"?>
        <datafile>
          <header><name>FinalBurn Neo - Arcade Games</name></header>
        \(games)</datafile>
        """
        try Data(dat.utf8).write(to: dats.appending(path: "fbneo.dat"))
        try zip(roms.appending(path: "ng0.zip"), ["p0.bin": chip(100)])
        let verifier = load(["ng0"])
        // No BIOS at all: the game can't start.
        #expect(verifier.check(roms.appending(path: "ng0.zip"), preferring: .fbneo, biosDirectory: bios)?.detail?.contains("neogeo.zip") == true)
        // One version of it, in the BIOS folder: enough.
        try zip(bios.appending(path: "neogeo.zip"), ["sp-s2.sp1": chip(10)])
        #expect(verifier.check(roms.appending(path: "ng0.zip"), preferring: .fbneo, biosDirectory: bios)?.verdict == .verified)
    }

    /// A game listed on its own whose chips are kept in another set's zip,
    /// and a game with BIOS versions of its own.
    @Test func chipsElsewhereAndAGamesOwnBIOS() throws {
        let dat = """
        <?xml version="1.0"?>
        <datafile>
          <header><name>FinalBurn Neo - Arcade Games</name></header>
          <game name="puzzle">
            <description>Puzzle</description>
            <rom name="p1.bin" size="1024" crc="\(crc(chip(1)))"/>
          </game>
          <game name="puzzler">
            <description>Puzzle R</description>
            <rom name="pr1.bin" size="1024" crc="\(crc(chip(2)))"/>
            <rom name="p1.bin" size="1024" crc="\(crc(chip(1)))"/>
          </game>
          <game name="maze">
            <description>Maze</description>
            <rom name="m1.bin" size="1024" crc="\(crc(chip(3)))"/>
            <rom name="maze-bios.sp1" size="1024" crc="\(crc(chip(4)))"/>
            <rom name="maze-bios_hack.sp1" size="1024" crc="\(crc(chip(5)))"/>
          </game>
        </datafile>
        """
        try Data(dat.utf8).write(to: dats.appending(path: "fbneo.dat"))
        try zip(roms.appending(path: "puzzle.zip"), ["p1.bin": chip(1)])
        try zip(roms.appending(path: "puzzler.zip"), ["pr1.bin": chip(2)])
        try zip(roms.appending(path: "maze.zip"), ["m1.bin": chip(3), "maze-bios.sp1": chip(4)])
        let verifier = load(["puzzle", "puzzler", "maze"])
        let puzzler = verifier.check(roms.appending(path: "puzzler.zip"), preferring: .fbneo, biosDirectory: bios)
        #expect(puzzler?.verdict == .incomplete)
        #expect(puzzler?.detail?.contains("puzzle.zip") == true)
        #expect(puzzler?.detail?.contains("p1.bin") == true)
        #expect(verifier.check(roms.appending(path: "maze.zip"), preferring: .fbneo, biosDirectory: bios)?.verdict == .verified)
    }

    @Test func arcadeDATsArentNoIntros() throws {
        try writeMAMEList()
        #expect(DATVerifier.load(from: dats).sets.isEmpty)
        #expect(ArcadeVerifier.isArcadeZip(URL(fileURLWithPath: "/x/mame0289lx.zip")))
    }
}
