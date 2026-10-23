import Testing
@testable import AtticModels

struct Switch2PadTests {

    /// Report 0x05 at rest: no buttons, both sticks centered (2048, 2048
    /// packed as 0x00 0x08 0x80).
    private var idleReport: [UInt8] {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = 0x05
        report[11] = 0x00; report[12] = 0x08; report[13] = 0x80
        report[14] = 0x00; report[15] = 0x08; report[16] = 0x80
        return report
    }

    @Test func restingPadIsNeutral() throws {
        let state = try #require(XInputPadState(switch2Report: idleReport))
        #expect(state.buttons.isEmpty)
        #expect(state.leftStickX == 0)
        #expect(state.leftStickY == 0)
        #expect(state.heldDirections().isEmpty)
    }

    @Test func faceButtonsMapByPosition() throws {
        var report = idleReport
        report[5] = 0b0000_0100 // B, the bottom button
        #expect(try #require(XInputPadState(switch2Report: report)).buttons == [.a])
        report[5] = 0b0000_1000 // A, the right one
        #expect(try #require(XInputPadState(switch2Report: report)).buttons == [.b])
        report[5] = 0b0000_0001 // Y, the left one
        #expect(try #require(XInputPadState(switch2Report: report)).buttons == [.x])
    }

    @Test func dpadShouldersAndZTriggers() throws {
        var report = idleReport
        report[7] = 0b1100_0010 // ZL, L, up
        report[5] = 0b1000_0000 // ZR
        let state = try #require(XInputPadState(switch2Report: report))
        #expect(state.buttons == [.dpadUp, .leftShoulder])
        #expect(state.leftTriggerPressed)
        #expect(state.rightTriggerPressed)
        #expect(state.heldDirections() == [.up])
    }

    @Test func stickPushedUpAndRightMoves() throws {
        var report = idleReport
        // X = 3600, Y = 3600: 0xE10 each.
        report[11] = 0x10; report[12] = 0x0E; report[13] = 0xE1
        let state = try #require(XInputPadState(switch2Report: report))
        #expect(state.heldDirections() == [.up, .right])
    }

    @Test func ignoresOtherReports() {
        var report = idleReport
        report[0] = 0x09
        #expect(XInputPadState(switch2Report: report) == nil)
        #expect(XInputPadState(switch2Report: [0x05, 0x00]) == nil)
    }
}
