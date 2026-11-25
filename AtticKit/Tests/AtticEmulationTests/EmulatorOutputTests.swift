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

    @Test func linesKeepTheirIndentAndLoseTrailingSpaces() {
        #expect(RunningGameSession.trimmed("[WARN] two \r") == "[WARN] two")
        #expect(RunningGameSession.trimmed("\tthree") == "\tthree")
        #expect(RunningGameSession.trimmed("  ") == nil)
    }

    /// A shell script standing in for an emulator.
    private func fakeEmulator(_ body: String) throws -> URL {
        let script = FileManager.default.temporaryDirectory.appending(path: "attic-fake-emulator-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @Test func emulatorOutputComesBackLineByLine() async throws {
        let lines = Mutex<[String]>([])
        let script = try fakeEmulator(#"printf '[INFO] one\n\n\tthree \r\n'; printf '[WARN] two\n' >&2"#)
        defer { try? FileManager.default.removeItem(at: script) }
        let session = try CustomEmulatorLauncher().launch(
            executableURL: script, argumentTemplate: "{romPath}", romURL: URL(filePath: "/dev/null"),
            onOutput: { line in lines.withLock { $0.append(line) } }
        )
        #expect(await session.waitUntilExit() == 0)
        #expect(Set(lines.withLock { $0 }) == ["[INFO] one", "\tthree", "[WARN] two"])
    }

    @Test func retroArchIsReadFromStandardErrorAlone() async throws {
        let lines = Mutex<[String]>([])
        let script = try fakeEmulator(#"echo "[INFO] out $*"; echo "[INFO] err" >&2"#)
        defer { try? FileManager.default.removeItem(at: script) }
        let session = try RetroArchLauncher(retroArchBinaryURL: script).launch(
            coreDylibURL: URL(filePath: "/dev/null"), romURL: URL(filePath: "/dev/null"),
            onOutput: { line in lines.withLock { $0.append(line) } }
        )
        #expect(session.commandLine.first == script.path)
        #expect(await session.waitUntilExit() == 0)
        #expect(lines.withLock { $0 } == ["[INFO] err"])
    }
}
