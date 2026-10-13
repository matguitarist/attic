import Foundation
import Testing
@testable import AtticLibraryScanning

struct DuplicateFinderTests {
    private func groups(_ names: [String]) throws -> [DuplicateFinder.Group] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Dupes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names { try Data().write(to: folder.appending(path: name)) }
        return DuplicateFinder.groups(in: folder)
    }

    @Test func keepsTheBestCopy() throws {
        let found = try groups([
            "Legend of Zelda, The (USA).zip",
            "Legend of Zelda, The (USA) (Rev 1).zip",
            "Legend of Zelda, The (Europe) (En,Fr,De).zip",
            "Legend of Zelda, The (Japan) (Beta).zip",
        ])
        #expect(found.count == 1)
        #expect(found[0].keep.lastPathComponent == "Legend of Zelda, The (USA) (Rev 1).zip")
        #expect(found[0].others.count == 3)
    }

    @Test func worldBeatsEverythingAndFinishedBeatsBeta() throws {
        let found = try groups(["Tetris (World).zip", "Tetris (USA).zip", "Sonic (USA) (Beta).md", "Sonic (Japan).md"])
        #expect(Set(found.map(\.keep.lastPathComponent)) == ["Tetris (World).zip", "Sonic (Japan).md"])
    }

    @Test func differentGamesStayApart() throws {
        let found = try groups([
            "Tetris (USA).zip", "Tetris (USA) (Tengen).zip", "Tetris (USA) (Unl).zip",
            "Final Fantasy VII (USA) (Disc 1).chd", "Final Fantasy VII (USA) (Disc 2).chd",
            "Game (USA).cue", "Game (Europe).cue",
            "Mario (USA).nes", "Mario (USA).fds",
        ])
        #expect(found.isEmpty)
    }

    @Test func aZipIsTheGameItHolds() throws {
        let found = try groups(["3-D WorldRunner (USA).nes", "3-D WorldRunner (USA).zip"])
        #expect(found.first?.keep.lastPathComponent == "3-D WorldRunner (USA).nes")
        #expect(found.first?.others.map(\.lastPathComponent) == ["3-D WorldRunner (USA).zip"])
    }

    @Test func badDumpsLoseToGoodOnes() throws {
        let found = try groups(["Contra (U) [b1].nes", "Contra (U) [!].nes"])
        #expect(found.first?.keep.lastPathComponent == "Contra (U) [!].nes")
    }
}
