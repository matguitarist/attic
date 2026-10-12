import Foundation
import Testing
@testable import AtticEmulation

@Suite struct ArgumentTemplateTests {

    private let rom = URL(fileURLWithPath: "/Users/tester/ROMs/n64/Ocarina of Time.z64")

    @Test func substitutesRomPath() {
        let args = ArgumentTemplate.substitute("--fullscreen {romPath}", romURL: rom)
        #expect(args == ["--fullscreen", "/Users/tester/ROMs/n64/Ocarina of Time.z64"])
    }

    @Test func substitutesAllFourPlaceholders() {
        let args = ArgumentTemplate.substitute(
            "{romDir} {romName} {romNameNoExt} {romPath}",
            romURL: rom
        )
        #expect(args == [
            "/Users/tester/ROMs/n64",
            "Ocarina of Time.z64",
            "Ocarina of Time",
            "/Users/tester/ROMs/n64/Ocarina of Time.z64"
        ])
    }

    @Test func pathWithSpacesStaysOneArgvElement() {
        let args = ArgumentTemplate.substitute("-f {romPath}", romURL: rom)
        #expect(args.count == 2)
        #expect(args[1] == "/Users/tester/ROMs/n64/Ocarina of Time.z64")
    }

    @Test func templateWithNoPlaceholdersPassesThroughLiterally() {
        let args = ArgumentTemplate.substitute("--batch --no-gui", romURL: rom)
        #expect(args == ["--batch", "--no-gui"])
    }

    @Test func emptyTemplateProducesNoArguments() {
        let args = ArgumentTemplate.substitute("", romURL: rom)
        #expect(args.isEmpty)
    }

    @Test func collapsesRepeatedWhitespaceBetweenTokens() {
        let args = ArgumentTemplate.substitute("-f   {romPath}", romURL: rom)
        #expect(args.count == 2)
    }
}
