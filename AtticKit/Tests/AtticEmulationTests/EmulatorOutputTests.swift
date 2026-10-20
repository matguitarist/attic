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

    @Test func splitsChunksIntoLines() {
        let lines = Mutex<[String]>([])
        let splitter = LineSplitter { line in lines.withLock { $0.append(line) } }
        splitter.feed(Data("[INFO] one\n[WA".utf8))
        splitter.feed(Data("RN] two\r\n\n\tthree".utf8))
        splitter.finish()
        #expect(lines.withLock { $0 } == ["[INFO] one", "[WARN] two", "\tthree"])
    }
}
