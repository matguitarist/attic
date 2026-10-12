import Foundation
import Testing
@testable import AtticEmulation

@Suite struct RetroArchCoreIndexTests {

    private func makeCoresAndInfoDirs() throws -> (cores: URL, info: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "attic-coreindex-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cores = root.appending(path: "cores")
        let info = root.appending(path: "info")
        try fm.createDirectory(at: cores, withIntermediateDirectories: true)
        try fm.createDirectory(at: info, withIntermediateDirectories: true)

        try Data().write(to: cores.appending(path: "snes9x_libretro.dylib"))
        try "corename = \"Snes9x\"\nsystemid = \"super_nes\"\nsupported_extensions = \"sfc|smc\""
            .write(to: info.appending(path: "snes9x_libretro.info"), atomically: true, encoding: .utf8)

        try Data().write(to: cores.appending(path: "nestopia_libretro.dylib"))
        try "corename = \"Nestopia\"\nsystemid = \"nes\"\nsupported_extensions = \"nes\""
            .write(to: info.appending(path: "nestopia_libretro.info"), atomically: true, encoding: .utf8)

        // A core with no matching .info file — should be skipped, not crash.
        try Data().write(to: cores.appending(path: "orphan_libretro.dylib"))

        // A non-dylib file in the cores dir — should be ignored.
        try Data().write(to: cores.appending(path: "README.txt"))

        return (cores, info)
    }

    @Test func scanFindsCoresWithMatchingInfoFiles() throws {
        let (cores, info) = try makeCoresAndInfoDirs()
        let results = RetroArchCoreIndex.scan(coresDirectory: cores, infoDirectory: info)

        #expect(results.count == 2)
        #expect(results.map(\.coreIdentifier).sorted() == ["nestopia_libretro", "snes9x_libretro"])
    }

    @Test func scanSortsByDisplayName() throws {
        let (cores, info) = try makeCoresAndInfoDirs()
        let results = RetroArchCoreIndex.scan(coresDirectory: cores, infoDirectory: info)

        #expect(results.map(\.displayName) == ["Nestopia", "Snes9x"])
    }

    @Test func scanOfMissingDirectoryReturnsEmptyWithoutThrowing() {
        let missing = FileManager.default.temporaryDirectory.appending(path: "attic-does-not-exist-\(UUID().uuidString)")
        let results = RetroArchCoreIndex.scan(coresDirectory: missing, infoDirectory: missing)
        #expect(results.isEmpty)
    }

    /// Regression test for a real bug: on at least one real RetroArch install
    /// (the Mac App Store build), `~/Library/Application Support/RetroArch/
    /// cores` is a symlink into a sandboxed container elsewhere. Foundation's
    /// `FileManager.contentsOfDirectory(at:)` fails with ENOTDIR ("Not a
    /// directory") on the unresolved symlink path even though the target is
    /// perfectly readable — confirmed against the real path on a real
    /// machine, where this silently produced zero cores (and a permanently
    /// disabled Play button) with no error surfaced anywhere. This is why
    /// `RetroArchInstallation.coresDirectoryURL`/`infoDirectoryURL` call
    /// `.resolvingSymlinksInPath()` before handing the URL to `scan`.
    @Test func scanOfUnresolvedSymlinkedDirectoryFindsNothingButResolvedPathWorks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "attic-coreindex-symlink-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        let realCores = root.appending(path: "real-cores")
        let realInfo = root.appending(path: "real-info")
        try fm.createDirectory(at: realCores, withIntermediateDirectories: true)
        try fm.createDirectory(at: realInfo, withIntermediateDirectories: true)
        try Data().write(to: realCores.appending(path: "nestopia_libretro.dylib"))
        try "corename = \"Nestopia\"\nsystemid = \"nes\"".write(
            to: realInfo.appending(path: "nestopia_libretro.info"), atomically: true, encoding: .utf8
        )

        let symlinkedCores = root.appending(path: "cores")
        try fm.createSymbolicLink(at: symlinkedCores, withDestinationURL: realCores)

        let unresolvedResults = RetroArchCoreIndex.scan(coresDirectory: symlinkedCores, infoDirectory: realInfo)
        #expect(unresolvedResults.isEmpty)

        let resolvedResults = RetroArchCoreIndex.scan(
            coresDirectory: symlinkedCores.resolvingSymlinksInPath(),
            infoDirectory: realInfo
        )
        #expect(resolvedResults.count == 1)
        #expect(resolvedResults.first?.coreIdentifier == "nestopia_libretro")
    }
}

struct RetroArchCoreIndexMultiDirectoryTests {
    @Test func firstCoresDirectoryWinsAndInfoFallsBackAcrossDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CoreIndexMulti-\(UUID().uuidString)")
        let atticCores = root.appending(path: "AtticCores")
        let retroArchCores = root.appending(path: "RetroArchCores")
        let emptyRetroArchInfo = root.appending(path: "RetroArchInfo")
        let atticInfo = root.appending(path: "AtticInfo")
        for directory in [atticCores, retroArchCores, emptyRetroArchInfo, atticInfo] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data().write(to: atticCores.appending(path: "snes9x_libretro.dylib"))
        try Data().write(to: retroArchCores.appending(path: "snes9x_libretro.dylib"))
        try Data().write(to: retroArchCores.appending(path: "mgba_libretro.dylib"))
        try "display_name = \"Snes9x\"\nsystemid = \"super_nes\"".write(to: atticInfo.appending(path: "snes9x_libretro.info"), atomically: true, encoding: .utf8)
        try "display_name = \"mGBA\"\nsystemid = \"game_boy_advance\"".write(to: atticInfo.appending(path: "mgba_libretro.info"), atomically: true, encoding: .utf8)

        let cores = RetroArchCoreIndex.scan(
            coresDirectories: [atticCores, retroArchCores],
            infoDirectories: [emptyRetroArchInfo, atticInfo]
        )

        #expect(cores.map(\.coreIdentifier) == ["mgba_libretro", "snes9x_libretro"])
        let snes9x = try #require(cores.first { $0.coreIdentifier == "snes9x_libretro" })
        #expect(snes9x.dylibURL.deletingLastPathComponent().lastPathComponent == "AtticCores")
    }
}
