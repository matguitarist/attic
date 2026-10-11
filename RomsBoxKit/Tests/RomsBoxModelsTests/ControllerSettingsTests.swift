import Foundation
import Testing
@testable import RomsBoxModels

struct ControllerSettingsTests {
    @Test func missingKeysFallBackToDefaults() throws {
        let settings = try JSONDecoder().decode(ControllerSettings.self, from: Data(#"{"layout":"nintendo"}"#.utf8))
        #expect(settings == ControllerSettings(layout: .nintendo))
        #expect(settings.quitWithSelectStart)
    }

    @Test func profilesRoundTrip() throws {
        let profile = ControllerProfile(name: "Couch", settings: .init(layout: .nintendo, buttonMapping: .faceButtonsSwapped, leftStickAsDPad: true))
        let decoded = try JSONDecoder().decode(ControllerProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }

    @Test func mappingStoresOnlyChangesAndEncodesAsADictionary() throws {
        var mapping = ButtonMapping.default
        mapping.set(.r1, for: .l2)
        mapping.set(.bottom, for: .b)   // its default: not stored
        #expect(mapping.overrides == [.l2: .r1])
        #expect(mapping.physical(for: .l2) == .r1)
        #expect(mapping.physical(for: .a) == .right)
        let json = String(decoding: try JSONEncoder().encode(mapping), as: UTF8.self)
        #expect(json == #"{"overrides":{"l2":"r1"}}"#)
    }

    @Test func ownedSettingsResetOnlyUntouchedValues() {
        let result = OwnedSettings.reconcile(
            desired: [("keep", "1")],
            previouslyWritten: ["keep": "1", "mine": "8", "changedByUser": "8"],
            current: ["mine": "8", "changedByUser": "3"],
            resetValue: { _ in "nul" }
        )
        #expect(result.write.map(\.key) == ["keep", "mine"])
        #expect(result.write.last?.value == "nul")
        #expect(result.written == ["keep": "1"])
    }
}
