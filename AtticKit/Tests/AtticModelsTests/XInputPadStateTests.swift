import Testing
@testable import AtticModels

struct XInputPadStateTests {

    /// Captured verbatim from an Amazon Luna controller over USB at rest.
    private let lunaIdleReport: [UInt8] = [
        0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00,
        0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]

    @Test func decodesRealIdleReportAsNeutral() throws {
        let state = try #require(XInputPadState(report: lunaIdleReport))
        #expect(state.buttons.isEmpty)
        #expect(state.leftStickX == -1)
        #expect(state.leftStickY == 0)
        #expect(state.heldDirections().isEmpty)
    }

    @Test func decodesLittleEndianButtonMask() throws {
        var report = lunaIdleReport
        // A (bit 12) + right shoulder (bit 9) + d-pad up (bit 0).
        report[2] = 0x01
        report[3] = 0x12
        let state = try #require(XInputPadState(report: report))
        #expect(state.buttons == [.a, .rightShoulder, .dpadUp])
        #expect(state.heldDirections() == [.up])
    }

    @Test func stickPastThresholdCountsAsDirection() throws {
        var report = lunaIdleReport
        // Left X = +30000 (0x7530), left Y = -30000 (0x8AD0).
        report[6] = 0x30; report[7] = 0x75
        report[8] = 0xD0; report[9] = 0x8A
        let state = try #require(XInputPadState(report: report))
        #expect(state.heldDirections() == [.right, .down])
    }

    @Test func rejectsNonInputMessages() {
        // LED status message: type 0x01.
        #expect(XInputPadState(report: [0x01, 0x03, 0x06]) == nil)
        #expect(XInputPadState(report: []) == nil)
    }
}
