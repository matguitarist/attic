// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AtticKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "AtticModels", targets: ["AtticModels"]),
        .library(name: "AtticPersistence", targets: ["AtticPersistence"]),
        .library(name: "AtticLibraryScanning", targets: ["AtticLibraryScanning"]),
        .library(name: "AtticEmulation", targets: ["AtticEmulation"]),
        .library(name: "AtticScraping", targets: ["AtticScraping"])
    ],
    targets: [
        .target(name: "AtticModels"),
        .target(name: "AtticPersistence", dependencies: ["AtticModels"]),
        .target(name: "AtticLibraryScanning", dependencies: ["AtticModels"]),
        // Resources holds the String Catalog for user-visible text
        // (emulator descriptions, install errors).
        .target(name: "AtticEmulation", dependencies: ["AtticModels"], resources: [.process("Resources")]),
        .target(name: "AtticScraping", dependencies: ["AtticModels"]),

        .testTarget(name: "AtticModelsTests", dependencies: ["AtticModels"]),
        .testTarget(name: "AtticPersistenceTests", dependencies: ["AtticPersistence"]),
        .testTarget(name: "AtticLibraryScanningTests", dependencies: ["AtticLibraryScanning"]),
        .testTarget(name: "AtticEmulationTests", dependencies: ["AtticEmulation"]),
        .testTarget(name: "AtticScrapingTests", dependencies: ["AtticScraping"])
    ]
)
