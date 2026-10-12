import Foundation
import Testing
@testable import AtticLibraryScanning
@testable import AtticModels

struct ImportedMediaTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "ImportedMedia-\(UUID().uuidString)")

    private func touch(_ path: String, _ text: String = "x") throws -> URL {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func findsBatoceraMedia() throws {
        let rom = try touch("atari2600/Pitfall.a26")
        _ = try touch("atari2600/images/Pitfall-boxart.png")
        _ = try touch("atari2600/images/Pitfall-image.png")
        _ = try touch("atari2600/images/Pitfall-marquee.png")
        _ = try touch("atari2600/videos/Pitfall-video.mp4")
        _ = try touch("atari2600/manuals/Pitfall-manual.pdf")
        let found = Dictionary(uniqueKeysWithValues: ImportedMedia.media(forROM: rom, system: .atari2600).map { ($0.kind, $0.file.lastPathComponent) })
        #expect(found == [.covers: "Pitfall-boxart.png", .screenshots: "Pitfall-image.png", .videos: "Pitfall-video.mp4", .manuals: "Pitfall-manual.pdf"])
    }

    @Test func findsMediaFoldersAndImagesBesideTheGame() throws {
        let rom = try touch("snes/Game.sfc")
        _ = try touch("snes/Game.png")
        _ = try touch("snes/snap/Game.png")
        _ = try touch("snes/Videos/Game.mp4")
        let found = Dictionary(uniqueKeysWithValues: ImportedMedia.media(forROM: rom, system: .snes).map { ($0.kind, $0.file.path) })
        #expect(found[.covers]?.hasSuffix("snes/Game.png") == true)
        #expect(found[.screenshots]?.hasSuffix("snap/Game.png") == true)
        #expect(found[.videos]?.hasSuffix("Videos/Game.mp4") == true)
    }

    @Test func findsAnESDETreeBesideTheROMsFolder() throws {
        let rom = try touch("Emulation/ROMs/nes/Zelda.nes")
        _ = try touch("Emulation/downloaded_media/nes/covers/Zelda.jpg")
        _ = try touch("Emulation/gamelists/nes/gamelist.xml")
        #expect(ImportedMedia.media(forROM: rom, system: .nes).map(\.kind) == [.covers])
        #expect(ImportedMedia.gamelist(near: rom.deletingLastPathComponent())?.path.hasSuffix("gamelists/nes/gamelist.xml") == true)
    }

    @Test func picoCartsAreGamesNotCovers() throws {
        let cart = try touch("pico8/celeste.p8.png")
        #expect(!ImportedMedia.isMedia(cart, for: .pico8))
        #expect(ImportedMedia.isMedia(cart, for: .snes))
    }

    @Test func gamelistsMergeWithoutDuplicates() throws {
        let folder = base.appending(path: "ROMs/cps1")
        _ = try touch("ROMs/cps1/1941.zip")
        _ = try touch("ROMs/cps1/ffight.zip")
        let existing = "<gameList>\n\t<game>\n\t\t<path>./1941.zip</path>\n\t\t<name>1941</name>\n\t</game>\n</gameList>"
        let incoming = """
        <gameList>
        \t<game>
        \t\t<path>./1941.zip</path>
        \t\t<name>Other 1941</name>
        \t</game>
        \t<game>
        \t\t<path>./ffight.zip</path>
        \t\t<name>Final Fight</name>
        \t\t<image>./images/ffight-image.png</image>
        \t</game>
        \t<game>
        \t\t<path>./gone.zip</path>
        \t</game>
        </gameList>
        """
        let merged = ImportedMedia.mergedGamelist(incoming, into: existing, systemFolder: folder)
        #expect(merged == "<gameList>\n\t<game>\n\t\t<path>./1941.zip</path>\n\t\t<name>1941</name>\n\t</game>\n\t<game>\n\t\t<path>./ffight.zip</path>\n\t\t<name>Final Fight</name>\n\t</game>\n</gameList>")
        #expect(ImportedMedia.mergedGamelist(incoming, into: nil, systemFolder: folder).contains("Other 1941"))
    }
}
