import Foundation
import Testing
@testable import RomsBoxEmulation

@Suite struct ZippedROMExtractorTests {
    private func makeExtractor(cacheDirectory: URL) -> ZippedROMExtractor {
        ZippedROMExtractor(cacheDirectory: cacheDirectory, unzipBinaryURL: URL(fileURLWithPath: "/usr/bin/unzip"))
    }

    private func isolatedCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "romsbox-extract-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// Builds a real zip file via `/usr/bin/zip` (not a hand-crafted fixture)
    /// so extraction is exercised against an actual archive, matching this
    /// project's preference for real fixtures over mocks where feasible.
    private func makeZip(named zipName: String, containing entries: [String: Data]) throws -> URL {
        let workDir = FileManager.default.temporaryDirectory.appending(path: "romsbox-zip-src-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        for (name, data) in entries {
            try data.write(to: workDir.appending(path: name))
        }

        let zipURL = workDir.appending(path: zipName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workDir
        process.arguments = [zipURL.path] + Array(entries.keys)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return zipURL
    }

    @Test func nonZipURLIsReturnedUnchanged() {
        let extractor = makeExtractor(cacheDirectory: isolatedCacheDirectory())
        let rom = URL(fileURLWithPath: "/tmp/Super Metroid.sfc")
        #expect(extractor.resolvedROMURL(for: rom) == rom)
    }

    @Test func singleFileZipExtractsToTheRealFile() throws {
        let romContents = Data("fake nes rom bytes".utf8)
        let zipURL = try makeZip(named: "720 Degrees (USA).zip", containing: ["720 Degrees (USA).nes": romContents])
        let extractor = makeExtractor(cacheDirectory: isolatedCacheDirectory())

        let resolved = extractor.resolvedROMURL(for: zipURL)

        #expect(resolved.lastPathComponent == "720 Degrees (USA).nes")
        #expect(resolved != zipURL)
        #expect(try Data(contentsOf: resolved) == romContents)
    }

    @Test func secondResolveReusesTheCachedExtractionRatherThanReExtracting() throws {
        let romContents = Data("fake gba rom bytes".utf8)
        let zipURL = try makeZip(named: "Metroid Fusion (USA).zip", containing: ["Metroid Fusion (USA).gba": romContents])
        let cacheDirectory = isolatedCacheDirectory()
        let extractor = makeExtractor(cacheDirectory: cacheDirectory)

        let first = extractor.resolvedROMURL(for: zipURL)
        let firstExtractedModDate = try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date

        let second = extractor.resolvedROMURL(for: zipURL)
        let secondExtractedModDate = try FileManager.default.attributesOfItem(atPath: second.path)[.modificationDate] as? Date

        #expect(first == second)
        #expect(firstExtractedModDate == secondExtractedModDate)
    }

    @Test func multiFileZipIsLeftUnresolvedRatherThanGuessing() throws {
        let zipURL = try makeZip(named: "multi-disc.zip", containing: [
            "Disc 1.bin": Data("disc1".utf8),
            "Disc 2.bin": Data("disc2".utf8)
        ])
        let extractor = makeExtractor(cacheDirectory: isolatedCacheDirectory())

        #expect(extractor.resolvedROMURL(for: zipURL) == zipURL)
    }

    @Test func emptyZipIsLeftUnresolved() throws {
        let workDir = FileManager.default.temporaryDirectory.appending(path: "romsbox-empty-zip-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let placeholder = workDir.appending(path: "placeholder.txt")
        try Data().write(to: placeholder)

        // Zip the file then delete the entry, leaving a technically-valid
        // but empty archive.
        let zipURL = workDir.appending(path: "empty.zip")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = workDir
        zipProcess.arguments = [zipURL.path, "placeholder.txt"]
        zipProcess.standardOutput = Pipe()
        zipProcess.standardError = Pipe()
        try zipProcess.run()
        zipProcess.waitUntilExit()

        let deleteProcess = Process()
        deleteProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        deleteProcess.arguments = ["-d", zipURL.path, "placeholder.txt"]
        deleteProcess.standardOutput = Pipe()
        deleteProcess.standardError = Pipe()
        try deleteProcess.run()
        deleteProcess.waitUntilExit()

        let extractor = makeExtractor(cacheDirectory: isolatedCacheDirectory())
        #expect(extractor.resolvedROMURL(for: zipURL) == zipURL)
    }

    @Test func chooseROMEntryIgnoresMacOSMetadataEntries() {
        let entries = ["__MACOSX/._Game.nes", "Game.nes"]
        #expect(ZippedROMExtractor.chooseROMEntry(from: entries) == "Game.nes")
    }

    @Test func chooseROMEntryReturnsNilForMultipleRealEntries() {
        let entries = ["Game.bin", "Game.cue"]
        #expect(ZippedROMExtractor.chooseROMEntry(from: entries) == nil)
    }

    @Test func chooseROMEntryReturnsNilForNoEntries() {
        #expect(ZippedROMExtractor.chooseROMEntry(from: []) == nil)
    }
}
