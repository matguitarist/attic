import Foundation
import Testing
import CryptoKit
@testable import AtticEmulation

@Suite("BIOS checksums")
struct BIOSChecksumsTests {
    private let bios: URL
    private let dump = Data(repeating: 0x42, count: 2048)
    private var entries: [BIOSChecksums.Entry] {
        let md5 = Insecure.MD5.hash(data: dump).map { String(format: "%02x", $0) }.joined()
        return [.init(name: "scph5501.bin", size: dump.count, md5: md5),
                .init(name: "pcsx2/bios/ps2-0200a.bin", size: dump.count, md5: md5)]
    }

    init() throws {
        bios = FileManager.default.temporaryDirectory.appending(path: "BIOSChecksumsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bios.appending(path: "pcsx2/bios"), withIntermediateDirectories: true)
    }

    @Test func theBundledListIsThere() {
        #expect(BIOSChecksums.entries.count > 400)
        #expect(!BIOSChecksums.known(for: "SCPH5501.BIN").isEmpty)
        #expect(!BIOSChecksums.known(for: "dc/dc_boot.bin").isEmpty)
        #expect(BIOSChecksums.known(for: "pcsx2/bios/").count > 20)
    }

    @Test func aKnownDumpIsVerified() throws {
        let file = bios.appending(path: "scph5501.bin")
        try dump.write(to: file)
        #expect(BIOSChecksums.verdict(of: file, as: "scph5501.bin", in: entries) == .verified)
        // Any dump PCSX2's folder takes.
        let ps2 = bios.appending(path: "pcsx2/bios/scph39001.bin")
        try dump.write(to: ps2)
        #expect(BIOSChecksums.verdict(of: ps2, as: "pcsx2/bios/", in: entries) == .verified)
    }

    @Test func aCopierHeaderIsSkipped() throws {
        let file = bios.appending(path: "scph5501.bin")
        try (Data(repeating: 0, count: 512) + dump).write(to: file)
        #expect(BIOSChecksums.verdict(of: file, as: "scph5501.bin", in: entries) == .verified)
    }

    @Test func aFolderDumpNotInTheListIsntFlagged() throws {
        let ps2 = bios.appending(path: "pcsx2/bios/scph30004r.bin")
        try Data(repeating: 1, count: 2048).write(to: ps2)
        #expect(BIOSChecksums.verdict(of: ps2, as: "pcsx2/bios/", in: entries) == .unchecked)
    }

    @Test func otherDataIsUnrecognized() throws {
        let file = bios.appending(path: "scph5501.bin")
        try Data(repeating: 1, count: 2048).write(to: file)
        #expect(BIOSChecksums.verdict(of: file, as: "scph5501.bin", in: entries) == .unrecognized)
        try Data(repeating: 1, count: 10).write(to: file)
        #expect(BIOSChecksums.verdict(of: file, as: "scph5501.bin", in: entries) == .unrecognized)
    }

    @Test func aCheckSaysWhatItCompared() throws {
        let file = bios.appending(path: "scph5501.bin")
        let other = Data(repeating: 1, count: 2048)
        try other.write(to: file)
        let check = BIOSChecksums.check(file, as: "scph5501.bin", in: entries)
        #expect(check.verdict == .unrecognized)
        #expect(check.expected.map(\.md5) == [entries[0].md5])
        #expect(check.md5 == Insecure.MD5.hash(data: other).map { String(format: "%02x", $0) }.joined())
        #expect(check.size == 2048)

        // In a folder: the dump it matched.
        let ps2 = bios.appending(path: "pcsx2/bios/x.bin")
        try dump.write(to: ps2)
        #expect(BIOSChecksums.check(ps2, as: "pcsx2/bios/", in: entries).expected.map(\.name) == ["pcsx2/bios/ps2-0200a.bin"])
    }

    @Test func zipsAndUnlistedFilesArentChecked() throws {
        let zip = bios.appending(path: "neogeo.zip")
        try dump.write(to: zip)
        #expect(BIOSChecksums.verdict(of: zip, as: "neogeo.zip", in: entries) == .unchecked)
        #expect(BIOSChecksums.verdict(of: zip, as: "other.bin", in: entries) == .unchecked)
    }

    @Test func findsAMissingFileUnderAnotherName() throws {
        try Data(repeating: 1, count: 2048).write(to: bios.appending(path: "decoy.bin"))
        try FileManager.default.createDirectory(at: bios.appending(path: "PS1"), withIntermediateDirectories: true)
        let misnamed = bios.appending(path: "PS1/PSX BIOS.bin")
        try dump.write(to: misnamed)
        #expect(BIOSChecksums.misnamedDump(of: "scph5501.bin", in: bios, entries: entries)?.lastPathComponent == "PSX BIOS.bin")
        #expect(BIOSChecksums.misnamedDump(of: "other.bin", in: bios, entries: entries) == nil)
    }
}
