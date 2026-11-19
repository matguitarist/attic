import Testing
@testable import AtticEmulation

struct TOMLSettingsTests {
    @Test func setsKeysInTheirTableAndKeepsTheRest() {
        var toml = TOMLSettings(contents: """
        [general]
        show_welcome = true

        [chihiro.roms]
        bios_path = 'old.bin'

        [display]
        fit = 'scale'
        """)
        toml.set(table: "chihiro.roms", key: "bios_path", string: "/BIOS/chihiro_xbox_bios.bin")
        toml.set(table: "chihiro.roms", key: "ic10_path", string: "/BIOS/ic10_g24lc64.bin")
        toml.set(table: "sys.files", key: "bootrom_path", string: "/BIOS/mcpx_1.0.bin")
        #expect(toml.contents == """
        [general]
        show_welcome = true

        [chihiro.roms]
        bios_path = '/BIOS/chihiro_xbox_bios.bin'
        ic10_path = '/BIOS/ic10_g24lc64.bin'

        [display]
        fit = 'scale'

        [sys.files]
        bootrom_path = '/BIOS/mcpx_1.0.bin'

        """)
        #expect(toml.value(table: "general", key: "show_welcome") == "true")
        #expect(toml.value(table: "display", key: "show_welcome") == nil)
    }

    @Test func startsAnEmptyFile() {
        var toml = TOMLSettings(contents: "")
        toml.set(table: "general", key: "show_welcome", bool: false)
        #expect(toml.contents == "[general]\nshow_welcome = false\n")
    }
}
