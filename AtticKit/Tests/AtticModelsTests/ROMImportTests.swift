import Foundation
import Testing
@testable import AtticModels

struct ROMImportTests {
    @Test func signatureTypesGoStraightToTheirSystem() {
        #expect(ROMImport.systems(forExtension: "SFC") == [.snes])
        #expect(ROMImport.systems(forExtension: "gb") == [.gb])
        #expect(ROMImport.systems(forExtension: "md") == [.genesis])
        #expect(ROMImport.systems(forExtension: "d64") == [.c64])
        #expect(ROMImport.systems(forExtension: "psvita") == [.psvita])
        #expect(ROMImport.systems(forExtension: "tic") == [.tic80])
    }

    @Test func sharedTypesOfferEverySystemThatTakesThem() {
        let iso = ROMImport.systems(forExtension: "iso")
        #expect(iso.count > 5)
        #expect(iso.contains(.ps2) && iso.contains(.gamecube))
        // Hack folders are never guessed.
        #expect(!ROMImport.systems(forExtension: "zip").contains { $0.isROMHacks })
        #expect(ROMImport.systems(forExtension: "docx").isEmpty)
    }

    @Test func filesGoToTheExistingFolderWhateverItsName() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ROMImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "MegaDrive"), withIntermediateDirectories: true)
        #expect(ROMImport.folder(for: .genesis, romsRoots: [root])?.lastPathComponent == "MegaDrive")
        #expect(ROMImport.folder(for: .snes, romsRoots: [root])?.lastPathComponent == "snes")
    }
}
