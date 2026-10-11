// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RomsBoxKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RomsBoxModels", targets: ["RomsBoxModels"]),
        .library(name: "RomsBoxPersistence", targets: ["RomsBoxPersistence"]),
        .library(name: "RomsBoxLibraryScanning", targets: ["RomsBoxLibraryScanning"]),
        .library(name: "RomsBoxEmulation", targets: ["RomsBoxEmulation"]),
        .library(name: "RomsBoxScraping", targets: ["RomsBoxScraping"])
    ],
    targets: [
        .target(name: "RomsBoxModels"),
        .target(name: "RomsBoxPersistence", dependencies: ["RomsBoxModels"]),
        .target(name: "RomsBoxLibraryScanning", dependencies: ["RomsBoxModels"]),
        // Resources holds the String Catalog for user-visible text
        // (emulator descriptions, install errors).
        .target(name: "RomsBoxEmulation", dependencies: ["RomsBoxModels"], resources: [.process("Resources")]),
        .target(name: "RomsBoxScraping", dependencies: ["RomsBoxModels"]),

        .testTarget(name: "RomsBoxModelsTests", dependencies: ["RomsBoxModels"]),
        .testTarget(name: "RomsBoxPersistenceTests", dependencies: ["RomsBoxPersistence"]),
        .testTarget(name: "RomsBoxLibraryScanningTests", dependencies: ["RomsBoxLibraryScanning"]),
        .testTarget(name: "RomsBoxEmulationTests", dependencies: ["RomsBoxEmulation"]),
        .testTarget(name: "RomsBoxScrapingTests", dependencies: ["RomsBoxScraping"])
    ]
)
