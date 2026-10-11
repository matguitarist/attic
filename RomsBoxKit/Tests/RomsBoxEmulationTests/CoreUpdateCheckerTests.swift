import Foundation
import Testing
@testable import RomsBoxEmulation

struct CoreUpdateCheckerTests {
    @Test func crc32MatchesZlibReferenceValues() {
        // Well-known CRC-32 check value for "123456789".
        #expect(CoreUpdateChecker.crc32(of: Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CoreUpdateChecker.crc32(of: Data()) == 0)
    }

    @Test func streamedFileCRCMatchesInMemoryCRC() throws {
        // Larger than one 1 MB read chunk, to cover the chunk boundary.
        let data = Data((0..<(3 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = FileManager.default.temporaryDirectory.appending(path: "crc-\(UUID().uuidString).bin")
        try data.write(to: url)
        #expect(try CoreUpdateChecker.crc32(ofFileAt: url) == CoreUpdateChecker.crc32(of: data))
    }

    @Test func parsesIndexExtended() {
        let index = """
        2026-10-11 78c759ac snes9x_libretro.dylib.zip
        2026-10-11 4a3d52b1 mesen_libretro.dylib.zip
        garbage line
        2026-10-11 zzzzzzzz broken_libretro.dylib.zip
        """
        #expect(CoreUpdateChecker.remoteChecksums(inIndexExtended: index) == [
            "snes9x_libretro": 0x78C7_59AC,
            "mesen_libretro": 0x4A3D_52B1
        ])
    }

    @Test func comparesInstalledFileWithRemoteChecksum() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "core-\(UUID().uuidString).dylib")
        try Data("core v1".utf8).write(to: url)
        let current = CoreUpdateChecker.crc32(of: Data("core v1".utf8))
        let newer = CoreUpdateChecker.crc32(of: Data("core v2".utf8))

        #expect(CoreUpdateChecker.status(ofCoreAt: url, coreIdentifier: "x_libretro", remoteChecksums: ["x_libretro": current]) == .upToDate)
        #expect(CoreUpdateChecker.status(ofCoreAt: url, coreIdentifier: "x_libretro", remoteChecksums: ["x_libretro": newer]) == .updateAvailable)
        #expect(CoreUpdateChecker.status(ofCoreAt: url, coreIdentifier: "x_libretro", remoteChecksums: [:]) == .notOnBuildbot)
    }
}
