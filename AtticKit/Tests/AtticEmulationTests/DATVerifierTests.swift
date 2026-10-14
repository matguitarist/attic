import Foundation
import Testing
@testable import AtticEmulation
import AtticModels

@Suite("DAT verification")
struct DATVerifierTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DATVerifierTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func crc(_ data: Data) -> String {
        String(format: "%08X", CoreUpdateChecker.crc32(of: data))
    }

    private func xml(name: String, games: [(String, String, Data)]) -> Data {
        let body = games.map { game, file, data in
            """
              <game name="\(game)">
                <description>\(game)</description>
                <rom name="\(file)" size="\(data.count)" crc="\(crc(data).lowercased())" sha1="0000"/>
              </game>
            """
        }.joined(separator: "\n")
        return Data("""
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/dats/datafile.dtd">
        <datafile>
          <header>
            <name>\(name)</name>
            <description>\(name)</description>
          </header>
        \(body)
        </datafile>
        """.utf8)
    }

    private func zip(_ data: Data, named name: String, into zipName: String) throws -> URL {
        let work = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try data.write(to: work.appending(path: name))
        let zip = folder.appending(path: zipName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-j", zip.path, work.appending(path: name).path]
        try process.run()
        process.waitUntilExit()
        return zip
    }

    @Test func theSameDumpUnderAnotherNameIsFound() throws {
        let rom = Data("cyber core".utf8)
        let bare = folder.appending(path: "Cyber Core (USA).pce")
        try rom.write(to: bare)
        let zipped = try zip(rom, named: "Cyber-Core (USA).pce", into: "Cyber-Core (USA).zip")
        let other = try zip(Data("cyber core 2".utf8), named: "Cyber-Core (USA).pce", into: "Other.zip")
        #expect(DATVerifier.sameDump(bare, zipped, system: .pcengine))
        #expect(!DATVerifier.sameDump(zipped, other, system: .pcengine))
        #expect(!DATVerifier.sameDump(zipped, folder.appending(path: "Missing.zip"), system: .pcengine))
    }

    @Test func readsDATOMATICXML() {
        let rom = Data("mario".utf8)
        let dat = DATFile.parse(xml(name: "Nintendo - Super Nintendo Entertainment System", games: [("Super Mario World (USA)", "Super Mario World (USA).sfc", rom)]))
        #expect(dat?.name == "Nintendo - Super Nintendo Entertainment System")
        #expect(dat?.roms == [DATFile.ROM(game: "Super Mario World (USA)", name: "Super Mario World (USA).sfc", size: 5, crc: CoreUpdateChecker.crc32(of: rom))])
        #expect(dat?.system == .snes)
    }

    @Test func readsClrmameproText() {
        let text = """
        clrmamepro (
        \tname "Nintendo - Game Boy"
        \tdescription "Nintendo - Game Boy"
        )

        game (
        \tname "Tetris (World) (Rev 1)"
        \tdescription "Tetris (World) (Rev 1)"
        \trom ( name "Tetris (World) (Rev 1).gb" size 32768 crc 46DF91AD md5 0 sha1 0 )
        )
        """
        let dat = DATFile.parse(Data(text.utf8))
        #expect(dat?.roms == [DATFile.ROM(game: "Tetris (World) (Rev 1)", name: "Tetris (World) (Rev 1).gb", size: 32768, crc: 0x46DF_91AD)])
        #expect(dat?.system == .gb)
    }

    @Test func namesNoIntroSetsByLibretrosNames() {
        #expect(DATFile(name: "Atari - Atari 2600", roms: []).system == .atari2600)
        #expect(DATFile(name: "Atari - Atari 7800 (A78)", roms: []).system == .atari7800)
        #expect(DATFile(name: "Nintendo - Nintendo Entertainment System (Headered)", roms: []).system == .nes)
        #expect(DATFile(name: "NEC - PC Engine - TurboGrafx-16", roms: []).system == .pcengine)
        #expect(DATFile(name: "Sega - 32X", roms: []).system == .sega32x)
        #expect(DATFile(name: "Atari - Atari Lynx (LNX)", roms: []).system == .atarilynx)
        #expect(DATFile(name: "Something Else", roms: []).system == nil)
    }

    @Test func verifiesAPlainFileAndAZip() throws {
        let rom = Data(repeating: 7, count: 4096)
        try xml(name: "Nintendo - Game Boy", games: [("Tetris (World)", "Tetris (World).gb", rom)]).write(to: folder.appending(path: "gb.dat"))
        let verifier = DATVerifier.load(from: folder)

        let plain = folder.appending(path: "My Tetris.gb")
        try rom.write(to: plain)
        #expect(verifier.check(plain, system: .gb) == .init(verdict: .verified, name: "Tetris (World)"))

        let zipped = try zip(rom, named: "Tetris (World).gb", into: "Tetris (World).zip")
        #expect(verifier.check(zipped, system: .gb) == .init(verdict: .verified, name: "Tetris (World)"))
    }

    @Test func aNamedGameWithOtherDataDiffers() throws {
        let rom = Data(repeating: 7, count: 4096)
        try xml(name: "Nintendo - Game Boy", games: [("Tetris (World)", "Tetris (World).gb", rom)]).write(to: folder.appending(path: "gb.dat"))
        let verifier = DATVerifier.load(from: folder)

        let altered = folder.appending(path: "Tetris (World).gb")
        try Data(repeating: 8, count: 4096).write(to: altered)
        #expect(verifier.check(altered, system: .gb) == .init(verdict: .differs, name: "Tetris (World)"))

        let homebrew = folder.appending(path: "My Game.gb")
        try Data(repeating: 9, count: 100).write(to: homebrew)
        #expect(verifier.check(homebrew, system: .gb) == .init(verdict: .unknown, name: nil))
        // No DAT for the system: nothing to say.
        #expect(verifier.check(homebrew, system: .snes) == nil)
    }

    @Test func aHeaderedNESGameMatchesAHeaderlessDAT() throws {
        let body = Data(repeating: 3, count: 40960)
        try xml(name: "Nintendo - Nintendo Entertainment System", games: [("10-Yard Fight (USA, Europe)", "10-Yard Fight (USA, Europe).nes", body)])
            .write(to: folder.appending(path: "nes.dat"))
        let verifier = DATVerifier.load(from: folder)
        let headered = Data("NES\u{1A}".utf8) + Data(repeating: 0, count: 12) + body
        let zipped = try zip(headered, named: "10-Yard Fight (USA, Europe) [!].nes", into: "10-Yard Fight.zip")
        #expect(verifier.check(zipped, system: .nes) == .init(verdict: .verified, name: "10-Yard Fight (USA, Europe)"))
    }

    @Test func aSNESCopierHeaderIsSkipped() throws {
        let body = Data(repeating: 5, count: 1024)
        try xml(name: "Nintendo - Super Nintendo Entertainment System", games: [("Game (USA)", "Game (USA).sfc", body)])
            .write(to: folder.appending(path: "snes.dat"))
        let file = folder.appending(path: "Game.smc")
        try (Data(repeating: 0, count: 512) + body).write(to: file)
        #expect(DATVerifier.load(from: folder).check(file, system: .snes)?.verdict == .verified)
    }

    @Test func readsA7zGame() throws {
        let rom = Data(repeating: 1, count: 2048)
        try xml(name: "Sega - 32X", games: [("Doom (USA)", "Doom (USA).32x", rom)]).write(to: folder.appending(path: "32x.dat"))
        let work = folder.appending(path: "work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try rom.write(to: work.appending(path: "Doom (USA).32x"))
        let archive = folder.appending(path: "Doom (USA).7z")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["--format", "7zip", "-cf", archive.path, "-C", work.path, "Doom (USA).32x"]
        try process.run()
        process.waitUntilExit()
        #expect(DATVerifier.load(from: folder).check(archive, system: .sega32x) == .init(verdict: .verified, name: "Doom (USA)"))
    }

    @Test func readsDATsInsideAZip() throws {
        let rom = Data(repeating: 2, count: 512)
        let datFolder = folder.appending(path: "dats", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: datFolder, withIntermediateDirectories: true)
        let datData = xml(name: "Nintendo - Game Boy Color", games: [("Game [b] (USA)", "Game [b] (USA).gbc", rom)])
        let pack = try zip(datData, named: "Nintendo - Game Boy Color (20260101-000000).dat", into: "dats/pack.zip")
        _ = pack
        let verifier = DATVerifier.load(from: datFolder)
        #expect(verifier.systems == [.gbc])
        let file = folder.appending(path: "x.gbc")
        try rom.write(to: file)
        #expect(verifier.check(file, system: .gbc)?.name == "Game [b] (USA)")
    }

    @Test func aGameOfSeveralFilesIsVerifiedWhenEachIs() throws {
        let rom = Data(repeating: 4, count: 4096)
        let save = Data(repeating: 6, count: 256)
        let dat = """
        clrmamepro ( name "Nintendo - Nintendo Entertainment System" )
        game ( name "Kid Dracula (World)"
        \trom ( name "Kid Dracula (World).nes" size 4096 crc \(crc(rom)) )
        \trom ( name "Kid Dracula (World).sav" size 256 crc \(crc(save)) )
        )
        """
        try Data(dat.utf8).write(to: folder.appending(path: "nes.dat"))
        let work = folder.appending(path: "kid", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try rom.write(to: work.appending(path: "a.nes"))
        try save.write(to: work.appending(path: "a.sav"))
        let zip = folder.appending(path: "Kid Dracula (World).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-j", zip.path, work.appending(path: "a.nes").path, work.appending(path: "a.sav").path]
        try process.run()
        process.waitUntilExit()
        let verifier = DATVerifier.load(from: folder)
        #expect(verifier.check(zip, system: .nes) == .init(verdict: .verified, name: "Kid Dracula (World)"))

        // A romset of files the DAT doesn't know isn't checked.
        try Data([9]).write(to: work.appending(path: "b.bin"))
        let other = folder.appending(path: "Other.zip")
        let more = Process()
        more.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        more.arguments = ["-q", "-j", other.path, work.appending(path: "a.nes").path, work.appending(path: "b.bin").path]
        try more.run()
        more.waitUntilExit()
        #expect(verifier.check(other, system: .nes) == nil)
    }

    @Test func aDumpListedUnderSeveralNamesKeepsTheOneItHas() {
        let names = ["Life Force (USA) (Rev 1)", "Life Force (USA) (Rev 1) (Virtual Console)"]
        #expect(DATVerifier.closest(to: "Life Force (USA) (Rev 1) (Virtual Console)", among: names) == names[1])
        #expect(DATVerifier.closest(to: "life force (usa) (rev 1)", among: names) == names[0])
        // Otherwise the nearest name, with the fewest extras.
        #expect(DATVerifier.closest(to: "Life Force (USA)", among: names) == names[0])
    }

    @Test func skipsDiscsAndRomsets() throws {
        try xml(name: "Sony - PlayStation", games: [("Game", "Game.bin", Data([1]))]).write(to: folder.appending(path: "psx.dat"))
        let chd = folder.appending(path: "Game.chd")
        try Data([1]).write(to: chd)
        #expect(DATVerifier.load(from: folder).check(chd, system: .psx) == nil)
    }
}
