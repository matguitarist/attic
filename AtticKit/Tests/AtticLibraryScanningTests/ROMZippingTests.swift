import Foundation
import Testing
@testable import AtticLibraryScanning
@testable import AtticModels

struct ROMZippingTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "Zip-\(UUID().uuidString)")

    private func write(_ path: String, _ data: Data) throws -> URL {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    private var compressible: Data { Data(repeating: 0x41, count: 64_000) }
    private var random: Data { Data((0..<64_000).map { _ in UInt8.random(in: 0...255) }) }

    @Test func findsLooseCartridges() throws {
        _ = try write("snes/Mario (USA).sfc", compressible)
        _ = try write("snes/Zelda (USA).sfc", compressible)
        _ = try write("snes/Zelda (USA).zip", compressible)
        _ = try write("snes/notes.txt", compressible)
        _ = try write("psx/Game.bin", compressible)
        _ = try write("snesh/Hack.sfc", compressible)
        let snes = ROMZipping.candidates(in: base.appending(path: "snes"), system: .snes)
        #expect(snes.map(\.lastPathComponent) == ["Mario (USA).sfc"])
        #expect(ROMZipping.candidates(in: base.appending(path: "psx"), system: .psx).isEmpty)
        #expect(ROMZipping.candidates(in: base.appending(path: "snesh"), system: .snesh).count == 1)
    }

    @Test func zipsWhenItSavesSpace() throws {
        let rom = try write("ROMs/snes/Mario (USA).sfc", compressible)
        let gamelist = try write("Gamelists/snes/gamelist.xml", Data("<gameList><game><path>./Mario (USA).sfc</path></game></gameList>".utf8))
        let zip = try #require(ROMZipping.zip(rom))
        #expect(zip.lastPathComponent == "Mario (USA).zip")
        #expect(!FileManager.default.fileExists(atPath: rom.path))
        #expect(try String(contentsOf: gamelist, encoding: .utf8).contains("./Mario (USA).zip"))
        // What Attic unzips at launch is the game, under its own name.
        let unzipped = ZippedROMCheck.entries(zip)
        #expect(unzipped == ["Mario (USA).sfc"])

        // Random data doesn't shrink: the ROM stays, and isn't offered again.
        let noise = try write("ROMs/snes/Noise.sfc", random)
        #expect(ROMZipping.zip(noise) == nil)
        #expect(FileManager.default.fileExists(atPath: noise.path))
        #expect(ROMZipping.candidates(in: base.appending(path: "ROMs/snes"), system: .snes).isEmpty)
        let hidden = try FileManager.default.contentsOfDirectory(atPath: base.appending(path: "ROMs/snes").path)
        #expect(Set(hidden) == ["Mario (USA).zip", "Noise.sfc"])
    }
}

private enum ZippedROMCheck {
    static func entries(_ zip: URL) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", zip.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
