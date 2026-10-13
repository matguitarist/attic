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
        echo "$@" >> "$(dirname "$0")/calls"
        case "$1" in
          create*) case "$3" in *bad*) exit 1;; esac; echo chd > "$5";;
          verify) exit 0;;
          extractcd) case "$3" in *bad*) echo half > "$5"; exit 1;; esac
            printf 'FILE "%s" BINARY\n' "$7" > "$5"; echo data > "$7";;
          extractdvd) echo iso > "$5";;
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

    /// A CHD v5 header with metadata entries tagged `tags`.
    private func fakeCHD(_ path: String, tags: [String], logicalBytes: UInt64 = 700_000_000) throws -> URL {
        var data = Data("MComprHD".utf8)
        func append(_ value: UInt64, _ count: Int) {
            for shift in stride(from: (count - 1) * 8, through: 0, by: -8) { data.append(UInt8((value >> UInt64(shift)) & 0xFF)) }
        }
        append(124, 4); append(5, 4)
        data.append(contentsOf: Array("cdlzcdzlcdfl".utf8) + [0, 0, 0, 0])
        append(logicalBytes, 8); append(0, 8)
        append(tags.isEmpty ? 0 : 124, 8)
        append(19_584, 4); append(2448, 4)
        data.append(contentsOf: [UInt8](repeating: 0, count: 20) + [UInt8](repeating: 0xAB, count: 20) + [UInt8](repeating: 0, count: 20))
        for (index, tag) in tags.enumerated() {
            let text = Data("TRACK:\(index + 1) TYPE:MODE2_RAW\0".utf8)
            data.append(contentsOf: Array(tag.utf8))
            append(UInt64(text.count), 4)
            append(index == tags.count - 1 ? 0 : UInt64(data.count + 8 + text.count), 8)
            data.append(text)
        }
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    @Test func readsTheHeader() throws {
        let cd = try #require(CHDHeader.read(try fakeCHD("a.chd", tags: ["CHT2", "CHT2", "CHT2"])))
        #expect(cd.kind == .cd && cd.tracks == 3 && cd.logicalBytes == 700_000_000)
        #expect(cd.codecs == ["cdlz", "cdzl", "cdfl"])
        #expect(cd.sha1 == String(repeating: "ab", count: 20))
        #expect(CHDHeader.read(try fakeCHD("b.chd", tags: ["CHGD", "CHGD"]))?.kind == .gdrom)
        let dvd = CHDHeader.read(try fakeCHD("c.chd", tags: ["DVD "]))
        #expect(dvd?.kind == .dvd && dvd?.tracks == nil)
        #expect(CHDHeader.read(try touch("d.chd", "not a chd at all, not at all, no")) == nil)
    }

    @Test func pspDiscsBecomeCHDsWithSmallHunks() throws {
        let chdman = try fakeCHDMan()
        _ = try touch("psp/Patapon (USA).iso")
        let found = CHDConversion.candidates(in: base.appending(path: "psp"), system: .psp)
        #expect(found.map(\.isDVD) == [true])
        #expect(CHDConversion.convert(try #require(found.first), chdman: chdman))
        let calls = try String(contentsOf: base.appending(path: "bin/calls"), encoding: .utf8)
        #expect(calls.contains("createdvd") && calls.contains("-hs 2048"))
    }

    @Test func aPlaylistsDiscsAreItsGame() throws {
        _ = try touch("psx/FF7 (Disc 1).cue", "FILE \"FF7 (Disc 1).bin\" BINARY\n")
        _ = try touch("psx/FF7 (Disc 1).bin")
        _ = try touch("psx/Other.cue", "FILE \"Other.bin\" BINARY\n")
        _ = try touch("psx/Other.bin")
        _ = try fakeCHD("psx/FF7 (Disc 2).chd", tags: ["CHT2"])
        let playlist = try touch("psx/FF7.m3u", "FF7 (Disc 1).cue\nFF7 (Disc 2).chd\n")
        #expect(CHDConversion.candidates(forGame: playlist, system: .psx).map(\.source.lastPathComponent) == ["FF7 (Disc 1).cue"])
        #expect(CHDConversion.chds(forGame: playlist).map(\.lastPathComponent) == ["FF7 (Disc 2).chd"])
    }

    @Test func turnsCHDsBack() throws {
        let chdman = try fakeCHDMan()
        let chd = try fakeCHD("ROMs/psx/Game (USA).chd", tags: ["CHT2"])
        _ = try touch("ROMs/psx/Game.m3u", "Game (USA).chd\n")
        let gamelist = try touch("Gamelists/psx/gamelist.xml", "<gameList><game><path>./Game (USA).chd</path></game></gameList>")
        #expect(CHDConversion.extract(chd, chdman: chdman))
        let folder = base.appending(path: "ROMs/psx")
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(names.isSuperset(of: ["Game (USA).cue", "Game (USA).bin"]) && !names.contains("Game (USA).chd"))
        #expect(try String(contentsOf: folder.appending(path: "Game.m3u"), encoding: .utf8) == "Game (USA).cue\n")
        #expect(try String(contentsOf: gamelist, encoding: .utf8).contains("<path>./Game (USA).cue</path>"))

        // A failed one leaves the CHD and nothing half-written.
        let bad = try fakeCHD("ROMs/psx/bad.chd", tags: ["CHT2"])
        #expect(!CHDConversion.extract(bad, chdman: chdman))
        #expect(FileManager.default.fileExists(atPath: bad.path))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "bad.cue").path))

        let dvd = try fakeCHD("ps2/Game.chd", tags: ["DVD "])
        #expect(CHDConversion.extract(dvd, chdman: chdman))
        #expect(FileManager.default.fileExists(atPath: base.appending(path: "ps2/Game.iso").path))
    }
}
