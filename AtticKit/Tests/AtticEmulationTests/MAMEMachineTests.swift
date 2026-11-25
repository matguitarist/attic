import Foundation
import Testing
import DownloadKit
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

struct PortLaunchTests {
    @Test func appsOpenAndScriptsRun() {
        #expect(PortLaunch(URL(filePath: "/ports/Ship of Harkinian.app")) == .app(URL(filePath: "/ports/Ship of Harkinian.app")))
        #expect(PortLaunch(URL(filePath: "/ports/Doom.command")) == .script(URL(filePath: "/ports/Doom.command")))
        #expect(PortLaunch(URL(filePath: "/ports/start.SH")) == .script(URL(filePath: "/ports/start.SH")))
        #expect(PortLaunch(URL(filePath: "/ports/readme.txt")) == nil)
    }

    @Test func scriptsRunFromTheirFolder() {
        let process = PortLaunch.scriptProcess(URL(filePath: "/ports/OpenGOAL/run.sh"))
        #expect(process.arguments == ["/ports/OpenGOAL/run.sh"])
        #expect(process.currentDirectoryURL?.path == "/ports/OpenGOAL")
    }

    @Test func portsFolderIsASystem() {
        #expect(SystemTaxonomy.system(forShortName: "ports")?.canonicalID == .ports)
        #expect(SystemROMExtensions.gameFolderExtensions.contains("app"))
    }
}

struct RyujinxTests {
    @Test func switchRunsInRyujinx() {
        let recommendation = EmulatorCatalog.recommendation(for: .switch)
        #expect(recommendation?.standalone.first?.id == "ryujinx")
        #expect(recommendation?.bios.first?.fileName == "switch/prod.keys")
        #expect(SystemROMExtensions.accepts("Game.nsp", for: .switch))
    }

    @Test func keysAreCopiedIntoRyujinxsDataFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = EmulationFolder(root: root)
        try FileManager.default.createDirectory(at: folder.bios.appending(path: "switch"), withIntermediateDirectories: true)
        try Data("keys".utf8).write(to: folder.bios.appending(path: "switch/prod.keys"))
        let arguments = try folder.ryujinxArguments()
        let data = folder.configHome(for: EmulatorCatalog.ryujinx)
        #expect(arguments == ["--root-data-dir", data.path])
        #expect(try Data(contentsOf: data.appending(path: "system/prod.keys")) == Data("keys".utf8))
        #expect(!FileManager.default.fileExists(atPath: data.appending(path: "system/title.keys").path))
    }

    @Test func releaseFeedNamesTheMacBuild() throws {
        let feed = #"{"id":50,"tag_name":"1.3.3","assets":[{"id":503,"name":"ryujinx-1.3.3-linux_x64.tar.gz","browser_download_url":"https://x/l.tar.gz"},{"id":504,"name":"ryujinx-1.3.3-macos_universal.app.tar.gz","browser_download_url":"https://x/m.tar.gz"}]}"#
        let release = EmulatorInstaller.release(in: try GitHubRelease.decode(Data(feed.utf8)), suffix: "-macos_universal.app.tar.gz")
        #expect(release?.downloadURL.absoluteString == "https://x/m.tar.gz")
        #expect(release?.version == "1.3.3")
    }
}
