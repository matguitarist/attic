import Foundation
import Testing
import AtticModels
@testable import AtticEmulation

struct GamePortsTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func doom3FilesNameTheirPakAndExpansionGetsItsCore() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appending(path: "Doom 3.boom3")
        let expansion = root.appending(path: "Resurrection of Evil.boom3")
        try "base\\pak000.pk4\r\n".write(to: base, atomically: true, encoding: .utf8)
        try "d3xp/pak000.pk4".write(to: expansion, atomically: true, encoding: .utf8)

        #expect(GamePorts.contentFile(for: base, system: .doom3).path == root.appending(path: "base/pak000.pk4").path)
        #expect(GamePorts.coreIdentifier(for: base, system: .doom3) == nil)
        #expect(GamePorts.coreIdentifier(for: expansion, system: .doom3) == "boom3_xp_libretro")
    }

    @Test func flashbackStartsFromItsFolder() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let game = root.appending(path: "Flashback.rem")
        try Data().write(to: game)
        let data = root.appending(path: "Flashback", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        for name in ["Instru_e.map", "Level1.map", "Level1.lev"] { try Data().write(to: data.appending(path: name)) }

        #expect(GamePorts.contentFile(for: game, system: .reminiscence).lastPathComponent == "Level1.map")
    }

    @Test func otherGamesAreGivenAsTheyAre() {
        let url = URL(fileURLWithPath: "/roms/dinothawr/dinothawr.game")
        #expect(GamePorts.contentFile(for: url, system: .dinothawr) == url)
    }
}
