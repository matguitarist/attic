import Foundation
import Testing
@testable import RomsBoxEmulation

@Suite struct CustomEmulatorLauncherTests {

    @Test func launchOfARealHarmlessProcessReportsTerminationAndExitCode() async throws {
        let launcher = CustomEmulatorLauncher()
        let session = try launcher.launch(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            argumentTemplate: "{romPath}",
            romURL: URL(fileURLWithPath: "/dev/null")
        )

        let exitCode = await session.waitUntilExit()
        #expect(exitCode == 0)
        #expect(session.isRunning == false)
    }

    @Test func launchOfNonexistentExecutableThrows() {
        let launcher = CustomEmulatorLauncher()
        #expect(throws: (any Error).self) {
            try launcher.launch(
                executableURL: URL(fileURLWithPath: "/nonexistent/SomeEmulator"),
                argumentTemplate: "{romPath}",
                romURL: URL(fileURLWithPath: "/dev/null")
            )
        }
    }
}
