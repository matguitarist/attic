import Foundation
import Testing
@testable import AtticLibraryScanning

struct ESDECustomCollectionTests {
    @Test func readsESDEAndBatoceraPaths() {
        let collection = ESDECustomCollection.parse("""
        %ROMPATH%/snes/Super Mario World (USA).sfc
        %ROMPATH%/nes/Hacks/Zelda Redux.nes
        /userdata/roms/megadrive/Sonic.zip
        C:\\Emulation\\ROMs\\gba\\Metroid Fusion.gba
        /some/other/psx/Game.chd

        # a note
        """, name: "Favourites")
        #expect(collection.entries == [
            .init(systemFolder: "snes", path: "Super Mario World (USA).sfc"),
            .init(systemFolder: "nes", path: "Hacks/Zelda Redux.nes"),
            .init(systemFolder: "megadrive", path: "Sonic.zip"),
            .init(systemFolder: "gba", path: "Metroid Fusion.gba"),
            .init(systemFolder: "psx", path: "Game.chd"),
        ])
    }

    @Test func namesComeFromTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "custom-Couch Co-op.cfg")
        try "%ROMPATH%/snes/A.sfc\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(ESDECustomCollection.read(url)?.name == "Couch Co-op")
        #expect(!ESDECustomCollection.isCollectionFile(URL(fileURLWithPath: "/tmp/es_settings.cfg")))
    }
}
