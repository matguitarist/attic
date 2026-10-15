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

    @Test func copiesAGameWithItsFiles() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "FrontEndCopy-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = base.appending(path: "psx", directoryHint: .isDirectory)
        let arcade = base.appending(path: "naomi", directoryHint: .isDirectory)
        let destination = base.appending(path: "mine", directoryHint: .isDirectory)
        for folder in [source, arcade.appending(path: "cvs2"), source.appending(path: "Folder Game.ps3")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        // A two-disc game: a playlist, each disc's cue and tracks.
        try "Game (Disc 1).cue\nGame (Disc 2).cue\n".write(to: source.appending(path: "Game.m3u"), atomically: true, encoding: .utf8)
        for disc in [1, 2] {
            try "FILE \"Game (Disc \(disc)) (Track 1).bin\" BINARY\n  TRACK 01 MODE2/2352\n"
                .write(to: source.appending(path: "Game (Disc \(disc)).cue"), atomically: true, encoding: .utf8)
            try Data("bin".utf8).write(to: source.appending(path: "Game (Disc \(disc)) (Track 1).bin"))
        }
        try Data("unrelated".utf8).write(to: source.appending(path: "Other.bin"))
        try Data("eboot".utf8).write(to: source.appending(path: "Folder Game.ps3/EBOOT.BIN"))
        try Data("zip".utf8).write(to: arcade.appending(path: "cvs2.zip"))
        try Data("chd".utf8).write(to: arcade.appending(path: "cvs2/gdx-0004.chd"))

        #expect(FrontEndMedia.files(ofGame: source.appending(path: "Game.m3u")).count == 5)
        let lead = FrontEndMedia.copyGame(source.appending(path: "Game.m3u"), from: source, to: destination)
        #expect(lead?.lastPathComponent == "Game.m3u")
        let copied = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        #expect(copied == ["Game (Disc 1) (Track 1).bin", "Game (Disc 1).cue", "Game (Disc 2) (Track 1).bin", "Game (Disc 2).cue", "Game.m3u"])
        // The source keeps its games.
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "Game.m3u").path))

        let arcadeCopy = base.appending(path: "mine-naomi", directoryHint: .isDirectory)
        _ = FrontEndMedia.copyGame(arcade.appending(path: "cvs2.zip"), from: arcade, to: arcadeCopy)
        #expect(FileManager.default.fileExists(atPath: arcadeCopy.appending(path: "cvs2/gdx-0004.chd").path))

        _ = FrontEndMedia.copyGame(source.appending(path: "Folder Game.ps3"), from: source, to: destination)
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Folder Game.ps3/EBOOT.BIN").path))
    }

    /// RetroBat's: discs in a MultiDisc folder, named the Windows way.
    @Test func copiesAMultiDiscGameAndMakesItsPlaylistWorkHere() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "FrontEndMultiDisc-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = base.appending(path: "psx", directoryHint: .isDirectory)
        let destination = base.appending(path: "mine", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "MultiDisc"), withIntermediateDirectories: true)
        for disc in [1, 2] { try Data("chd".utf8).write(to: source.appending(path: "MultiDisc/Wild Arms 2 (USA) (Disc \(disc)).chd")) }
        let playlist = source.appending(path: "Wild Arms 2 (MultiDisc).m3u")
        try Data("\\MultiDisc\\Wild Arms 2 (USA) (Disc 1).chd\r\n\\MultiDisc\\Wild Arms 2 (USA) (Disc 2).chd\r\n".utf8).write(to: playlist)

        #expect(FrontEndMedia.files(ofGame: playlist).count == 3)
        _ = FrontEndMedia.copyGame(playlist, from: source, to: destination)
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "MultiDisc/Wild Arms 2 (USA) (Disc 2).chd").path))
        #expect(try String(contentsOf: destination.appending(path: "Wild Arms 2 (MultiDisc).m3u"), encoding: .utf8)
                == "MultiDisc/Wild Arms 2 (USA) (Disc 1).chd\nMultiDisc/Wild Arms 2 (USA) (Disc 2).chd\n")
        // The source is left as it was.
        #expect(try Data(contentsOf: playlist).contains(UInt8(ascii: "\\")))
    }

    @Test func readsAGDI() {
        let gdi = "3\n1 0 4 2352 track01.bin 0\n2 756 0 2352 \"track 02.raw\" 0\n3 45000 4 2352 track03.bin 0\n"
        #expect(FrontEndMedia.referencedFiles(in: gdi, playlist: false, sheet: false) == ["track01.bin", "track 02.raw", "track03.bin"])
    }
}
