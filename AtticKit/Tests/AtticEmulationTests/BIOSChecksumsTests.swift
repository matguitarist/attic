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

    // MARK: - Zipped sets

    private func zip(_ name: String, _ files: [String: Data]) throws -> URL {
        let work = bios.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        for (file, data) in files { try data.write(to: work.appending(path: file)) }
        let url = bios.appending(path: name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-j", url.path] + files.keys.sorted().map { work.appending(path: $0).path }
        try process.run()
        process.waitUntilExit()
        return url
    }

    private func chip(_ byte: UInt8) -> Data { Data(repeating: byte, count: 1024) }

    /// A board with two BIOS revisions, a chip both need and an EEPROM's
    /// default contents.
    private var board: [BIOSChecksums.Chip] {
        func make(_ revision: String, _ name: String, _ byte: UInt8, required: Bool = true) -> BIOSChecksums.Chip {
            .init(set: "board", revision: revision, name: name, size: 1024, crc: CoreUpdateChecker.crc32(of: chip(byte)), required: required)
        }
        return [make("bios0", "new.ic27", 1), make("bios1", "old.ic27", 2), make("", "pic.ic31", 3), make("", "eeprom.bin", 4, required: false)]
    }

    @Test func aZippedSetIsCheckedByItsChips() throws {
        // One revision is enough, under any name; the EEPROM isn't needed.
        let good = try zip("good.zip", ["renamed.bin": chip(2), "pic.ic31": chip(3)])
        let check = BIOSChecksums.checkSet(good, chips: board, list: "MAME 0.289")
        #expect(check.verdict == .verified)
        #expect(check.setList == "MAME 0.289")

        // No revision: one revision's chips are what's missing.
        let noBIOS = try zip("nobios.zip", ["pic.ic31": chip(3)])
        let missing = BIOSChecksums.checkSet(noBIOS, chips: board, list: "MAME")
        #expect(missing.verdict == .unrecognized)
        #expect(missing.needsRevision)
        #expect(missing.missingChips.map(\.name) == ["new.ic27"])

        // Named right, other data.
        let bad = try zip("bad.zip", ["new.ic27": chip(9), "old.ic27": chip(2), "pic.ic31": chip(3)])
        let other = BIOSChecksums.checkSet(bad, chips: board, list: "MAME")
        #expect(other.verdict == .unrecognized)
        #expect(other.otherChips.map(\.name) == ["new.ic27"])
        #expect(other.missingChips.isEmpty)
    }

    @Test func everyZippedBIOSAtticAsksForIsListed() {
        #expect(BIOSChecksums.sets.list.hasPrefix("MAME "))
        for set in ["dc/naomi.zip", "dc/naomi2.zip", "dc/awbios.zip", "mame/bios/hikaru.zip", "mame/bios/mie.zip",
                    "mame/bios/jvs13551.zip", "mame/bios/model1io.zip", "mame/bios/model1io2.zip", "neogeo.zip", "same_cdi/bios/cdimono1.zip"] {
            #expect(!BIOSChecksums.chips(for: set).isEmpty, "\(set)")
        }
        // Hikaru's current BIOS.
        #expect(BIOSChecksums.chips(for: "hikaru.zip").contains { $0.name == "epr-23400a.ic94" && $0.crcText == "2aa906a7" })
    }
}
