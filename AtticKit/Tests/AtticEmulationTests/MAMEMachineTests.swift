import Foundation
import Testing
import AtticModels
@testable import AtticEmulation

struct MAMEMachineTests {
    @Test func commandLinePutsTheGameInTheMachinesSlot() throws {
        let machine = try #require(MAMEMachine.machine(for: .apple2))
        let line = machine.commandLine(
            romURL: URL(filePath: "/ROMs/apple2/Karateka (USA).dsk"),
            romPaths: [URL(filePath: "/ROMs/apple2"), URL(filePath: "/Emulation/BIOS")]
        )
        #expect(line == #"apple2ee -flop1 "/ROMs/apple2/Karateka (USA).dsk" -rompath "/ROMs/apple2;/Emulation/BIOS""#)
    }

    @Test func extensionPicksTheSlot() throws {
        let coco = try #require(MAMEMachine.machine(for: .coco))
        #expect(coco.media(for: URL(filePath: "/a/Game.ccc")) == "cart")
        #expect(coco.media(for: URL(filePath: "/a/Game.CAS")) == "cass")
        #expect(coco.media(for: URL(filePath: "/a/Game.dsk")) == "flop1")
    }

    @Test func autobootIsTypedAfterBoot() throws {
        let lynx = try #require(MAMEMachine.machine(for: .camplynx))
        let line = lynx.commandLine(romURL: URL(filePath: "/r/Game.tap"), romPaths: [URL(filePath: "/b")])
        #expect(line == #"lynx48k -cass "/r/Game.tap" -autoboot_delay 2 -autoboot_command mload"" -rompath "/b""#)
    }

    @Test func lcdGamesAreRomsets() throws {
        #expect(try #require(MAMEMachine.machine(for: .lcdgames)).runsRomsets)
        #expect(MAMEMachine.machine(for: .snes) == nil)
    }

    @Test func autobootCommandsHaveNoDots() {
        // The MAME core puts a folder in front of any argument with a dot
        // that follows an option, so an autoboot with one would break.
        for system in SystemTaxonomy.allSystems {
            if let autoboot = MAMEMachine.machine(for: system.canonicalID)?.autoboot {
                #expect(!autoboot.contains("."), "\(system.canonicalID)")
            }
        }
    }

    @Test func writesTheCommandFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let emulation = EmulationFolder(root: folder)
        let file = try #require(try emulation.mameCommandFile(
            for: .ti99, romURL: URL(filePath: "/r/Parsec.rpk"), gameFolder: URL(filePath: "/r")
        ))
        #expect(file.pathExtension == "cmd")
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix(#"ti99_4a -cart "/r/Parsec.rpk""#))
        #expect(try emulation.mameCommandFile(for: .lcdgames, romURL: URL(filePath: "/r/gnw_mario.zip"), gameFolder: URL(filePath: "/r")) == nil)
    }

    @Test func everyMAMESystemListsItsSet() {
        let apple2 = EmulatorCatalog.recommendation(for: .apple2)
        #expect(apple2?.bios.contains { $0.fileName == "apple2ee.zip" && !$0.required } == true)
        #expect(apple2?.recommendedCore?.coreIdentifier == "applewin_libretro")
    }

    @Test func newSystemsFromBatoceraAndRetroBatAreKnown() {
        for folder in ["apple2", "bbcmicro", "coco", "ti99", "advision", "vsmile", "lcdgames", "sgb", "fmtowns", "oric", "dragon64", "multivision"] {
            #expect(SystemTaxonomy.system(forShortName: folder) != nil, "\(folder)")
        }
    }
}
