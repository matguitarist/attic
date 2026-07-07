// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RomsBoxKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RomsBoxModels", targets: ["RomsBoxModels"]),
        .library(name: "RomsBoxPersistence", targets: ["RomsBoxPersistence"]),
        .library(name: "RomsBoxLibraryScanning", targets: ["RomsBoxLibraryScanning"]),
        .library(name: "RomsBoxEmulation", targets: ["RomsBoxEmulation"])
    ],
    targets: [
        .target(name: "RomsBoxModels"),
        .target(name: "RomsBoxPersistence", dependencies: ["RomsBoxModels"]),
        .target(name: "RomsBoxLibraryScanning", dependencies: ["RomsBoxModels"]),
        .target(name: "RomsBoxEmulation", dependencies: ["RomsBoxModels"]),

        .testTarget(name: "RomsBoxModelsTests", dependencies: ["RomsBoxModels"]),
        .testTarget(name: "RomsBoxLibraryScanningTests", dependencies: ["RomsBoxLibraryScanning"]),
        .testTarget(name: "RomsBoxEmulationTests", dependencies: ["RomsBoxEmulation"])
    ]
)
