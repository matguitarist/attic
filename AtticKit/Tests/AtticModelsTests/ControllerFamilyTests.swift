import Testing
@testable import AtticModels

struct ControllerFamilyTests {

    @Test(arguments: [
        ("Xbox Wireless Controller", ControllerFamily.xbox),
        ("Amazon Luna Controller", .xbox),
        ("Some Generic Pad", .xbox),
        ("DualSense Wireless Controller", .playStation),
        ("Wireless Controller", .playStation),
        ("Pro Controller", .nintendo),
        ("Joy-Con (L/R)", .nintendo),
        ("8BitDo Pro 2", .eightBitDo),
        ("8BitDo Ultimate Wireless / Pro 2 Wired Controller for Xbox", .eightBitDo),
        ("Stadia Controller rev. A", .stadia),
    ])
    func detectsFromTheName(name: String, family: ControllerFamily) {
        #expect(ControllerFamily.detect(name: name) == family)
    }

    @Test func detectsFromGameControllersCategory() {
        #expect(ControllerFamily.detect(name: "Controller", category: "DualShock 4") == .playStation)
        #expect(ControllerFamily.detect(name: nil, category: "Switch Pro Controller") == .nintendo)
    }

    @Test func faceButtonsKeepTheirPrintedLabels() {
        #expect(ControllerFamily.xbox.glyph(for: .bottom) == .symbol("a.circle.fill"))
        #expect(ControllerFamily.playStation.glyph(for: .bottom) == .symbol("xmark.circle.fill"))
        #expect(ControllerFamily.nintendo.glyph(for: .bottom) == .symbol("b.circle.fill"))
        #expect(ControllerFamily.eightBitDo.glyph(for: .top) == .symbol("x.circle.fill"))
        #expect(ControllerFamily.stadia.glyph(for: .select) == .symbol("ellipsis.circle.fill"))
    }

    @Test func theKeyboardConfirmsWithReturnWhicheverButtonConfirms() {
        #expect(ControllerFamily.keyboard.glyph(for: .bottom, layout: .classic) == .symbol("return"))
        #expect(ControllerFamily.keyboard.glyph(for: .right, layout: .classic) == .symbol("escape"))
        #expect(ControllerFamily.keyboard.glyph(for: .right, layout: .nintendo) == .symbol("return"))
        #expect(ControllerFamily.keyboard.glyph(for: .bottom, layout: .nintendo) == .symbol("escape"))
    }
}
