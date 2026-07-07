import Foundation
import Testing
@testable import RomsBoxEmulation
@testable import RomsBoxModels

@Suite struct RetroArchCoreInfoParserTests {

    // Real content from installed cores' .info files (nestopia, snes9x,
    // genesis_plus_gx, mgba, mednafen_psx), confirmed against an actual
    // RetroArch installation rather than guessed.
    private let snes9xInfo = """
    corename = "Snes9x"
    supported_extensions = "smc|sfc|swc|fig|bs|st"
    systemname = "Super Nintendo Entertainment System"
    systemid = "super_nes"
    """

    private let genesisPlusGXInfo = """
    supported_extensions = "mdx|md|smd|gen|bin|cue|iso|sms|bms|gg|sg|68k|sgd|chd|m3u"
    corename = "Genesis Plus GX"
    systemname = "Sega 8/16-bit (Various)"
    systemid = "mega_drive"
    """

    private let mgbaInfo = """
    supported_extensions = "gb|gbc|gba"
    corename = "mGBA"
    systemname = "Game Boy/Game Boy Color/Game Boy Advance"
    systemid = "game_boy_advance"
    """

    @Test func parsesQuotedFields() {
        let info = RetroArchCoreInfoParser.parse(
            contents: snes9xInfo,
            coreIdentifier: "snes9x_libretro",
            dylibURL: URL(fileURLWithPath: "/cores/snes9x_libretro.dylib")
        )

        #expect(info.displayName == "Snes9x")
        #expect(info.supportedExtensions == ["smc", "sfc", "swc", "fig", "bs", "st"])
        #expect(info.systemID == "super_nes")
        #expect(info.canonicalSystemID == .snes)
        #expect(info.coreIdentifier == "snes9x_libretro")
    }

    @Test func fieldOrderDoesNotMatter() {
        let info = RetroArchCoreInfoParser.parse(
            contents: genesisPlusGXInfo,
            coreIdentifier: "genesis_plus_gx_libretro",
            dylibURL: URL(fileURLWithPath: "/cores/genesis_plus_gx_libretro.dylib")
        )

        #expect(info.displayName == "Genesis Plus GX")
        #expect(info.systemID == "mega_drive")
        #expect(info.canonicalSystemID == .genesis)
    }

    @Test func mgbaCoreResolvesToCanonicalGBA() {
        let info = RetroArchCoreInfoParser.parse(
            contents: mgbaInfo,
            coreIdentifier: "mgba_libretro",
            dylibURL: URL(fileURLWithPath: "/cores/mgba_libretro.dylib")
        )

        #expect(info.canonicalSystemID == .gba)
        #expect(info.supportedExtensions.contains("gba"))
    }

    @Test func unrecognizedSystemIDYieldsNilCanonicalSystem() {
        let info = RetroArchCoreInfoParser.parse(
            contents: "corename = \"Some Arcade Core\"\nsystemid = \"totally_unknown_system\"",
            coreIdentifier: "somearcade_libretro",
            dylibURL: URL(fileURLWithPath: "/cores/somearcade_libretro.dylib")
        )

        #expect(info.canonicalSystemID == nil)
    }

    @Test func missingCorenameFallsBackToCoreIdentifier() {
        let info = RetroArchCoreInfoParser.parse(
            contents: "supported_extensions = \"nes\"",
            coreIdentifier: "somecore_libretro",
            dylibURL: URL(fileURLWithPath: "/cores/somecore_libretro.dylib")
        )

        #expect(info.displayName == "somecore_libretro")
        #expect(info.supportedExtensions == ["nes"])
    }
}
