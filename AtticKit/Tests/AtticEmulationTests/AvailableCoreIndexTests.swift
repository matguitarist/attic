import Foundation
import Testing
@testable import AtticEmulation
@testable import AtticModels

struct AvailableCoreIndexTests {
    private let infoDirectory: URL

    init() throws {
        infoDirectory = FileManager.default.temporaryDirectory.appending(path: "AvailableCores-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: infoDirectory, withIntermediateDirectories: true)
        // Real field values from libretro's info files.
        try write("genesis_plus_gx_libretro", """
            corename = "Genesis Plus GX"
            systemid = "mega_drive"
            database = "Sega - Game Gear|Sega - Master System - Mark III|Sega - Mega-CD - Sega CD|Sega - Mega Drive - Genesis|Sega - PICO|Sega - SG-1000"
            """)
        try write("swanstation_libretro", """
            corename = "SwanStation"
            systemid = "playstation"
            database = "Sony - PlayStation"
            """)
        try write("madeup_libretro", """
            corename = "LRPS2"
            systemid = "madeup"
            database = "Made-Up Computer"
            """)
        try write("x86only_libretro", """
            corename = "Not on arm64"
            systemid = "nes"
            database = "Nintendo - Nintendo Entertainment System"
            """)
    }

    private func write(_ identifier: String, _ contents: String) throws {
        try contents.write(to: infoDirectory.appending(path: "\(identifier).info"), atomically: true, encoding: .utf8)
    }

    @Test func databaseFieldMapsAMultiSystemCoreToEverySystem() throws {
        let cores = AvailableCoreIndex.scan(infoDirectory: infoDirectory)
        let genesisPlusGX = try #require(cores.first { $0.coreIdentifier == "genesis_plus_gx_libretro" })
        #expect(Set(genesisPlusGX.systems) == [.genesis, .mastersystem, .gamegear, .segacd, .sg1000])
        #expect(genesisPlusGX.systems.first == .genesis, "systemid's system stays first")
    }

    @Test func coresForSystemsAtticDoesntKnowAreLeftOut() {
        let identifiers = AvailableCoreIndex.scan(infoDirectory: infoDirectory).map(\.coreIdentifier)
        #expect(!identifiers.contains("madeup_libretro"))
    }

    @Test func availabilityListFiltersToBuiltCores() throws {
        try "genesis_plus_gx_libretro\nswanstation_libretro\n"
            .write(to: infoDirectory.appending(path: AvailableCoreIndex.availabilityFileName), atomically: true, encoding: .utf8)
        let identifiers = AvailableCoreIndex.scan(infoDirectory: infoDirectory).map(\.coreIdentifier)
        #expect(identifiers == ["genesis_plus_gx_libretro", "swanstation_libretro"])
    }

    @Test func withoutAvailabilityListEveryKnownCoreIsListed() {
        let identifiers = AvailableCoreIndex.scan(infoDirectory: infoDirectory).map(\.coreIdentifier)
        #expect(identifiers.contains("x86only_libretro"))
    }

    @Test func parsesBuildbotDirectoryListing() {
        let html = """
        <a href="/nightly/apple/osx/arm64/latest/snes9x_libretro.dylib.zip">snes9x</a>
        <a href="/nightly/apple/osx/arm64/latest/mesen_libretro.dylib.zip">mesen</a>
        <a href="/nightly/apple/osx/arm64/latest/snes9x_libretro.dylib.zip">dup</a>
        <a href="/nightly/apple/osx/arm64/">..</a>
        """
        #expect(AvailableCoreIndex.coreIdentifiers(inBuildbotIndex: html) == ["mesen_libretro", "snes9x_libretro"])
    }
}
