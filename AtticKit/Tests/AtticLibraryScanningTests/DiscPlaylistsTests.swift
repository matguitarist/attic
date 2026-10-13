import Foundation
import Testing
@testable import AtticLibraryScanning
@testable import AtticModels

struct DiscPlaylistsTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: "Discs-\(UUID().uuidString)")

    private func touch(_ path: String) throws -> URL {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func readsDiscTags() {
        #expect(DiscPlaylists.disc(in: "Final Fantasy VII (USA) (Disc 2)")! == ("Final Fantasy VII (USA)", 2))
        #expect(DiscPlaylists.disc(in: "Policenauts (Japan) (Disk 1 of 3)")! == ("Policenauts (Japan)", 1))
        #expect(DiscPlaylists.disc(in: "Tekken 3 (USA)") == nil)
    }

    @Test func readsTheTracksOfCueAndGdiSheets() {
        #expect(DiscPlaylists.partName(#"FILE "Game (Track 1).bin" BINARY"#, in: "cue") == "Game (Track 1).bin")
        #expect(DiscPlaylists.partName("  TRACK 01 MODE2/2352", in: "cue") == nil)
        #expect(DiscPlaylists.partName("3", in: "gdi") == nil)
        #expect(DiscPlaylists.partName(#"1 0 4 2352 "track01.bin" 0"#, in: "gdi") == "track01.bin")
        #expect(DiscPlaylists.partName("2 756 0 2352 track02.raw 0", in: "gdi") == "track02.raw")
    }

    @Test func makesOnePlaylistPerSetAndHidesItsDiscs() throws {
        for disc in 1...3 {
            _ = try touch("ROMs/psx/Final Fantasy VII (USA) (Disc \(disc)).cue")
            _ = try touch("ROMs/psx/Final Fantasy VII (USA) (Disc \(disc)).bin")
        }
        _ = try touch("ROMs/psx/Metal Gear Solid (USA) (Disc 1).chd")
        _ = try touch("ROMs/psx/Metal Gear Solid (USA) (Disc 2).chd")
        _ = try touch("ROMs/psx/Tekken 3 (USA).chd")
        _ = try touch("Media/psx/covers/Final Fantasy VII (USA) (Disc 1).heic")
        let psx = base.appending(path: "ROMs/psx")

        #expect(DiscPlaylists.createMissing(romsRoots: [base.appending(path: "ROMs")]) == 2)
        let ff7 = try String(contentsOf: psx.appending(path: "Final Fantasy VII (USA).m3u"), encoding: .utf8)
        #expect(ff7 == "Final Fantasy VII (USA) (Disc 1).cue\nFinal Fantasy VII (USA) (Disc 2).cue\nFinal Fantasy VII (USA) (Disc 3).cue\n")
        // The game takes disc 1's cover.
        #expect(FileManager.default.fileExists(atPath: base.appending(path: "Media/psx/covers/Final Fantasy VII (USA).heic").path))
        // Once there, it isn't made again.
        #expect(DiscPlaylists.missing(in: psx).isEmpty)
        #expect(DiscPlaylists.listedFiles(in: psx).contains("Metal Gear Solid (USA) (Disc 2).chd"))
    }
}
