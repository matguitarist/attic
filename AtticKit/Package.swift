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
    dependencies: [
        .package(url: "https://github.com/matguitarist/PictureKit", from: "0.2.1"),
        .package(url: "https://github.com/matguitarist/ProcessKit", from: "0.2.2"),
        .package(url: "https://github.com/matguitarist/ArchiveKit", from: "0.2.0"),
        .package(url: "https://github.com/matguitarist/DownloadKit", from: "0.2.0"),
        .package(url: "https://github.com/matguitarist/FileKit", from: "0.2.0")
    ],
    targets: [
        .target(name: "AtticModels"),
        .target(name: "AtticPersistence", dependencies: ["AtticModels"]),
        .target(name: "AtticLibraryScanning", dependencies: ["AtticModels", .product(name: "PictureKit", package: "PictureKit"),
                                                     .product(name: "ProcessKit", package: "ProcessKit"),
                                                     .product(name: "ArchiveKit", package: "ArchiveKit"),
                                                     .product(name: "FileKit", package: "FileKit")]),
        // Resources holds the String Catalog for user-visible text
        // (emulator descriptions, install errors).
        .target(name: "AtticEmulation", dependencies: ["AtticModels", "AtticLibraryScanning", .product(name: "ProcessKit", package: "ProcessKit"),
                                                .product(name: "ArchiveKit", package: "ArchiveKit"),
                                                .product(name: "DownloadKit", package: "DownloadKit"),
                                                .product(name: "FileKit", package: "FileKit")],
                resources: [.process("Resources")]),
        .target(name: "AtticScraping", dependencies: ["AtticModels"]),

        .testTarget(name: "AtticModelsTests", dependencies: ["AtticModels"]),
        .testTarget(name: "AtticPersistenceTests", dependencies: ["AtticPersistence"]),
        .testTarget(name: "AtticLibraryScanningTests", dependencies: ["AtticLibraryScanning", .product(name: "PictureKit", package: "PictureKit"),
                                                               .product(name: "ArchiveKit", package: "ArchiveKit")]),
        .testTarget(name: "AtticEmulationTests", dependencies: ["AtticEmulation", "AtticLibraryScanning", .product(name: "ArchiveKit", package: "ArchiveKit"),
                                                         .product(name: "DownloadKit", package: "DownloadKit")]),
        .testTarget(name: "AtticScrapingTests", dependencies: ["AtticScraping"])
    ]
)
