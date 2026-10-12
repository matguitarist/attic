import Foundation
import Testing
@testable import AtticEmulation

@Suite struct RetroArchLauncherTests {

    @Test func buildsExpectedArgumentArray() {
        let core = URL(fileURLWithPath: "/Users/tester/Library/Application Support/RetroArch/cores/snes9x_libretro.dylib")
        let rom = URL(fileURLWithPath: "/Users/tester/ROMs/snes/Super Metroid.sfc")

        let arguments = RetroArchLauncher.buildArguments(coreDylibURL: core, romURL: rom)

        #expect(arguments == ["-L", core.path, rom.path])
    }

    @Test func launchOfARealHarmlessProcessReportsTerminationAndExitCode() async throws {
        // Exercises the real Process/RunningGameSession plumbing end-to-end
        // without needing RetroArch installed: point the launcher's "binary"
        // at /usr/bin/true, which takes no useful arguments but exits 0
        // immediately — proving spawn + isRunning + waitUntilExit() work.
        let launcher = RetroArchLauncher(retroArchBinaryURL: URL(fileURLWithPath: "/usr/bin/true"))
        let session = try launcher.launch(
            coreDylibURL: URL(fileURLWithPath: "/dev/null"),
            romURL: URL(fileURLWithPath: "/dev/null")
        )

        let exitCode = await session.waitUntilExit()
        #expect(exitCode == 0)
        #expect(session.isRunning == false)
    }

    @Test func launchOfNonexistentBinaryThrows() {
        let launcher = RetroArchLauncher(retroArchBinaryURL: URL(fileURLWithPath: "/nonexistent/RetroArch"))
        #expect(throws: (any Error).self) {
            try launcher.launch(
                coreDylibURL: URL(fileURLWithPath: "/dev/null"),
                romURL: URL(fileURLWithPath: "/dev/null")
            )
        }
    }
}

struct RetroArchLauncherPortableArgumentsTests {
    @Test func configArgumentsComeBeforeCoreAndContent() {
        let arguments = RetroArchLauncher.buildArguments(
            coreDylibURL: URL(fileURLWithPath: "/E/Cores/snes9x_libretro.dylib"),
            romURL: URL(fileURLWithPath: "/E/ROMs/snes/Game.sfc"),
            configURL: URL(fileURLWithPath: "/E/Config/RetroArch/retroarch.cfg"),
            appendConfigURL: URL(fileURLWithPath: "/E/Config/RetroArch/attic-paths.cfg")
        )
        #expect(arguments == [
            "--config", "/E/Config/RetroArch/retroarch.cfg",
            "--appendconfig", "/E/Config/RetroArch/attic-paths.cfg",
            "-L", "/E/Cores/snes9x_libretro.dylib",
            "/E/ROMs/snes/Game.sfc"
        ])
    }
}
