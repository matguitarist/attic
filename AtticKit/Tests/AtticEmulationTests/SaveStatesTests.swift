import Foundation
import Testing
@testable import AtticEmulation

struct SaveStatesTests {
    @Test func listsNumberedStatesWithTheirPictures() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["Sonic (USA).state", "Sonic (USA).state.png", "Sonic (USA).state3", "Sonic (USA).state.auto",
                     "Sonic (USA).srm", "Sonic 2 (USA).state1", "Sonic (USA).state3.png"] {
            try Data().write(to: folder.appending(path: name))
        }
        let states = SaveState.list(in: folder, romURL: URL(filePath: "/roms/Sonic (USA).zip"))
        #expect(Set(states.map(\.slot)) == [0, 3])
        #expect(states.allSatisfy { $0.thumbnail != nil })
        #expect(states.first { $0.slot == 3 }?.launchArguments == ["--entryslot", "3"])
    }

    @Test func slotSuffixes() {
        #expect(SaveState.slot(of: "") == 0)
        #expect(SaveState.slot(of: "12") == 12)
        #expect(SaveState.slot(of: ".auto") == nil)
        #expect(SaveState.slot(of: "3.png") == nil)
    }
}
