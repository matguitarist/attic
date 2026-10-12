import Foundation
import Testing
@testable import AtticModels

struct ROMHacksTests {
    @Test func hackFoldersAreSystemsOfTheirOwn() throws {
        let snesh = try #require(SystemTaxonomy.system(forShortName: "snesh"))
        #expect(snesh.canonicalID == .snesh)
        #expect(snesh.displayName == "\(SystemTaxonomy.definition(for: .snes)!.displayName) Hacks")
        #expect(snesh.category == .console)
        #expect(SystemTaxonomy.system(forShortName: "megadriveh")?.canonicalID == .genesish)
        #expect(SystemTaxonomy.system(forShortName: "gbah")?.category == .handheld)
    }

    @Test func theyPlayLikeTheirBaseSystem() {
        #expect(CanonicalSystemID.snesh.baseSystem == .snes)
        #expect(CanonicalSystemID.snes.baseSystem == .snes)
        #expect(CanonicalSystemID.psxh.isROMHacks)
        #expect(SystemROMExtensions.accepts("Super Mario World - Kaizo (Hack).sfc", for: .snesh))
        #expect(!SystemROMExtensions.accepts("readme.txt", for: .snesh))
    }

    @Test func everyFolderNameIsUnique() {
        let names = SystemTaxonomy.allSystems.flatMap(\.allShortNames)
        #expect(names.count == Set(names).count)
    }
}

struct GameFolderTests {
    @Test func coresGetTheFileInsideAGameFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GameFolder-\(UUID().uuidString)")
        let scumm = root.appending(path: "Monkey Island.scummvm")
        let quake = root.appending(path: "Quake.quake")
        let ps3 = root.appending(path: "Demon's Souls.ps3")
        for url in [scumm.appending(path: "Monkey Island.scummvm"), quake.appending(path: "id1/pak0.pak"), ps3.appending(path: "PS3_GAME/PARAM.SFO")] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        #expect(SystemROMExtensions.launchFile(forGameFolder: scumm).lastPathComponent == "Monkey Island.scummvm")
        #expect(SystemROMExtensions.launchFile(forGameFolder: quake).path.hasSuffix("Quake.quake/id1/pak0.pak"))
        #expect(SystemROMExtensions.launchFile(forGameFolder: ps3) == ps3)
        #expect(SystemROMExtensions.accepts("Monkey Island.scummvm", for: .scummvm))
    }
}
