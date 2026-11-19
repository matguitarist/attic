import Testing
@testable import AtticModels

struct ArcadeMakerTests {
    @Test func readsMAMEManufacturers() {
        #expect(ArcadeMaker.id(forManufacturer: "Cave (AMI license)") == "cave")
        #expect(ArcadeMaker.id(forManufacturer: "Data East Corporation") == "dataeast")
        #expect(ArcadeMaker.id(forManufacturer: "Raizing / Eighting") == "raizing")
        #expect(ArcadeMaker.id(forManufacturer: "Taito Corporation Japan") == "taito")
        #expect(ArcadeMaker.id(forManufacturer: "Bally Midway") == "midway")
        #expect(ArcadeMaker.id(forManufacturer: "Video System Co.") == "videosystem")
        #expect(ArcadeMaker.id(forManufacturer: "Seibu Kaihatsu (Tad license)") == "seibukaihatsu")
        #expect(ArcadeMaker.id(forManufacturer: "SNK") == "snk")
    }

    @Test func leavesOthersOut() {
        #expect(ArcadeMaker.id(forManufacturer: "") == nil)
        #expect(ArcadeMaker.id(forManufacturer: "bootleg") == nil)
        // A name that only starts like a maker's isn't it.
        #expect(ArcadeMaker.id(forManufacturer: "Segasa") == nil)
        #expect(ArcadeMaker.id(forManufacturer: "Caveman Games") == nil)
    }
}
