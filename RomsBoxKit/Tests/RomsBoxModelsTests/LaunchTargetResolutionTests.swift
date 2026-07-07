import Foundation
import Testing
@testable import RomsBoxModels

@Suite struct LaunchTargetResolutionTests {

    private let override = LaunchTargetReference.emulatorProfile(id: UUID())
    private let systemDefault = LaunchTargetReference.retroArchCore(coreIdentifier: "snes9x_libretro")

    @Test func gameOverrideWinsWhenBothArePresent() {
        let resolved = LaunchTargetResolution.resolve(gameOverride: override, systemDefault: systemDefault)
        #expect(resolved == override)
    }

    @Test func systemDefaultIsUsedWhenNoOverride() {
        let resolved = LaunchTargetResolution.resolve(gameOverride: nil, systemDefault: systemDefault)
        #expect(resolved == systemDefault)
    }

    @Test func nilWhenNeitherIsConfigured() {
        let resolved = LaunchTargetResolution.resolve(gameOverride: nil, systemDefault: nil)
        #expect(resolved == nil)
    }

    @Test func overrideAloneIsUsedWhenNoSystemDefault() {
        let resolved = LaunchTargetResolution.resolve(gameOverride: override, systemDefault: nil)
        #expect(resolved == override)
    }
}
