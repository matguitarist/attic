import Foundation
import Testing
@testable import AtticLibraryScanning

struct FrontEndMediaTests {
    @Test func readsARetroBatSystemFolder() throws {
        let roms = FileManager.default.temporaryDirectory.appending(path: "FrontEnd-\(UUID().uuidString)/roms", directoryHint: .isDirectory)
        let nes = roms.appending(path: "nes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nes.appending(path: "images"), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: nes.appending(path: "images/1942 (Japan, USA) (En)-thumb.png"))
        try Data("png".utf8).write(to: nes.appending(path: "images/1942 (Japan, USA) (En)-image.png"))
        try """
        <?xml version="1.0"?>
        <gameList>
          <game>
            <path>./1942 (Japan, USA) (En).zip</path>
            <name>1942</name>
            <desc>Fly.</desc>
            <developer>Capcom</developer>
            <releasedate>19851211T000000</releasedate>
            <rating>0.6</rating>
            <thumbnail>./images/1942 (Japan, USA) (En)-thumb.png</thumbnail>
            <image>./images/1942 (Japan, USA) (En)-image.png</image>
            <video>./videos/1942 (Japan, USA) (En)-video.mp4</video>
          </game>
        </gameList>
        """.write(to: nes.appending(path: "gamelist.xml"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: roms.appending(path: "notasystem"), withIntermediateDirectories: true)

        let systems = FrontEndMedia.systems(in: roms)
        #expect(systems.count == 1)
        #expect(systems.first?.system.rawValue == "nes")
        let entry = systems.first?.entries["1942 (japan, usa) (en)"]
        #expect(entry?.description == "Fly.")
        #expect(entry?.developer == "Capcom")
        #expect(entry?.rating == 0.6)
        #expect(entry?.releaseDate != nil)
        #expect(entry?.cover?.lastPathComponent == "1942 (Japan, USA) (En)-thumb.png")
        #expect(entry?.screenshot?.lastPathComponent == "1942 (Japan, USA) (En)-image.png")
        // Named, but not there.
        #expect(entry?.video == nil)
        // One system's folder on its own.
        #expect(FrontEndMedia.systems(in: nes).count == 1)
    }
}
