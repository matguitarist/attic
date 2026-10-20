import Foundation
import Synchronization
import Testing
@testable import AtticEmulation

@Suite("Emulator output")
struct EmulatorOutputTests {
    @Test func readsRetroArchLevels() {
        #expect(EmulatorOutput.parse("[INFO] [Content]: Loading content file: sf2.zip") == (.info, "[Content]: Loading content file: sf2.zip"))
        #expect(EmulatorOutput.parse("[WARN] [Video]: Shader failed").level == .warning)
        #expect(EmulatorOutput.parse("[ERROR] Failed to load content.").level == .error)
        #expect(EmulatorOutput.parse("[DEBUG] [Input]: x").level == .debug)
    }

    @Test func marksTheCoresOwnLines() {
        let (level, message) = EmulatorOutput.parse("[libretro ERROR] Required files are missing, the machine cannot be run.")
        #expect(level == .error)
        #expect(message == "[Core] Required files are missing, the machine cannot be run.")
    }

    @Test func judgesFreeTextByItsWords() {
        #expect(EmulatorOutput.parse("sf2.zip NOT FOUND (tried in sf2)").level == .error)
        #expect(EmulatorOutput.parse("Warning: config file not writable").level == .warning)
        #expect(EmulatorOutput.parse("Starting Dolphin 2412").level == .info)
    }

    @Test func quietsMoltenVKAndListings() {
        #expect(EmulatorOutput.parse("[mvk-warn] VK_ERROR_FEATURE_NOT_PRESENT: Metal does not support disabling primitive restart.")
            == (.debug, "[MoltenVK] VK_ERROR_FEATURE_NOT_PRESENT: Metal does not support disabling primitive restart."))
        #expect(EmulatorOutput.parse("\tVK_KHR_16bit_storage v1") == (.debug, "VK_KHR_16bit_storage v1"))
    }

    @Test func quietsHarmlessWarnings() {
        #expect(EmulatorOutput.parse("[WARN] [Environ] GET_VFS_INTERFACE. Core requested version V4 which is higher than what we support (V3).").level == .debug)
        #expect(EmulatorOutput.parse("c31boot.bin ROM NEEDS REDUMP").level == .warning)
        #expect(EmulatorOutput.parse("sf2.bin WRONG CHECKSUMS:").level == .error)
    }

    /// Speed Up, as MAME 0.289 logged it through RetroArch.
    @Test func diagnosesAnIncompleteMAMESet() {
        let diagnosis = LaunchDiagnosis()
        let lines = [
            "[libretro INFO] MAME 0.289 (5f5a0774)",
            "[libretro INFO] Game description: Speed Up (version 2.20, checksum 2037)",
            "[libretro ERROR] m.2x1_covi_152b6_pic16c54.bin NOT FOUND (tried in speedup)",
            "a1_a_4426_pal16l8.bin NOT FOUND (tried in speedup)",
            "m1_c_2af3_pal16l8.bin NOT FOUND (tried in speedup)",
            "c31boot.bin ROM NEEDS REDUMP",
            "prg.ic1 WRONG CHECKSUMS:",
        ]
        for line in lines { #expect(!diagnosis.read(line)) }
        #expect(diagnosis.problem == nil)
        #expect(diagnosis.read("[libretro ERROR] Fatal error: Required files are missing, the machine cannot be run."))
        #expect(!diagnosis.read("[ERROR] [Content] Failed to load content."))
        #expect(diagnosis.problem == LaunchProblem(
            emulator: "MAME 0.289",
            missingFiles: ["m.2x1_covi_152b6_pic16c54.bin", "a1_a_4426_pal16l8.bin", "m1_c_2af3_pal16l8.bin"],
            wrongFiles: ["prg.ic1"],
            fatalMessage: "Required files are missing, the machine cannot be run."
        ))
    }

    @Test func aGameThatRunsHasNoProblem() {
        let diagnosis = LaunchDiagnosis()
        diagnosis.read("[libretro INFO] Game name: 1942")
        diagnosis.read("[INFO] [Core] Geometry: 256x224")
        #expect(diagnosis.problem == nil)
    }

    @Test func splitsChunksIntoLines() {
        let lines = Mutex<[String]>([])
        let splitter = LineSplitter { line in lines.withLock { $0.append(line) } }
        splitter.feed(Data("[INFO] one\n[WA".utf8))
        splitter.feed(Data("RN] two\r\n\n\tthree".utf8))
        splitter.finish()
        #expect(lines.withLock { $0 } == ["[INFO] one", "[WARN] two", "\tthree"])
    }
}
