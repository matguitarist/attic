import Foundation
import Testing
@testable import AtticLibraryScanning
@testable import AtticModels

struct CHDConversionTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "CHD-\(UUID().uuidString)")

    private func touch(_ path: String, _ text: String = "x") throws -> URL {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// Stands in for chdman: "createcd/createdvd -i in -o out" writes out,
    /// "verify" passes — unless the input's name says "bad".
    private func fakeCHDMan() throws -> URL {
        let script = try touch("bin/chdman", """
        #!/bin/sh
        case "$1" in
          create*) case "$3" in *bad*) exit 1;; esac; echo chd > "$5";;
          verify) exit 0;;
        esac
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @Test func findsDiscGamesWithAllTheirTracks() throws {
        let cue = try touch("psx/Game (USA).cue", "FILE \"Game (USA) (Track 1).bin\" BINARY\nFILE \"Game (USA) (Track 2).bin\" BINARY\n")
        _ = try touch("psx/Game (USA) (Track 1).bin")
        _ = try touch("psx/Game (USA) (Track 2).bin")
        _ = try touch("psx/Broken (USA).cue", "FILE \"Missing.bin\" BINARY\n")
        _ = try touch("psx/Done (USA).cue", "FILE \"Done.bin\" BINARY\n")
        _ = try touch("psx/Done.bin")
        _ = try touch("psx/Done (USA).chd")
        let found = CHDConversion.candidates(in: base.appending(path: "psx"), system: .psx)
        #expect(found.map(\.source.lastPathComponent) == [cue.lastPathComponent])
        #expect(found.first?.files.count == 3)
        #expect(CHDConversion.candidates(in: base.appending(path: "psx"), system: .snes).isEmpty)
    }

    @Test func convertsVerifiesThenReplaces() throws {
        let chdman = try fakeCHDMan()
        _ = try touch("psx/FF7 (Disc 1).cue", "FILE \"FF7 (Disc 1).bin\" BINARY\n")
        _ = try touch("psx/FF7 (Disc 1).bin")
        _ = try touch("psx/FF7.m3u", "FF7 (Disc 1).cue\nFF7 (Disc 2).chd\n")
        _ = try touch("psx/bad (USA).cue", "FILE \"bad.bin\" BINARY\n")
        _ = try touch("psx/bad.bin")
        let folder = base.appending(path: "psx")
        let candidates = CHDConversion.candidates(in: folder, system: .psx)
        let results = candidates.map { CHDConversion.convert($0, chdman: chdman) }
        #expect(results == [true, false])

        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(names.contains("FF7 (Disc 1).chd") && !names.contains("FF7 (Disc 1).cue") && !names.contains("FF7 (Disc 1).bin"))
        // A failed one keeps its files and leaves no CHD behind.
        #expect(names.contains("bad (USA).cue") && !names.contains("bad (USA).chd"))
        #expect(try String(contentsOf: folder.appending(path: "FF7.m3u"), encoding: .utf8) == "FF7 (Disc 1).chd\nFF7 (Disc 2).chd\n")
    }
}
