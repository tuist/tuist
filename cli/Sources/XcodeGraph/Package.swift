// swift-tools-version:5.10
import PackageDescription

let targets: [Target] = [
    .target(
        name: "XcodeGraph",
        dependencies: [
            .product(name: "AnyCodable", package: "flight-school.AnyCodable"),
            .product(name: "Path", package: "tuist.Path"),
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
        ]
    ),
    .target(
        name: "XcodeMetadata",
        dependencies: [
            .product(name: "FileSystem", package: "tuist.FileSystem"),
            .product(name: "Mockable", package: "kolos65.Mockable"),
            .product(name: "MachOKitC", package: "p-x9.MachOKit"),
            "XcodeGraph",
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .testTarget(
        name: "XcodeMetadataTests",
        dependencies: ["XcodeMetadata", "XcodeGraph"],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
        ]
    ),
    .target(
        name: "XcodeGraphMapper",
        dependencies: [
            "XcodeGraph",
            "XcodeMetadata",
            .product(name: "Command", package: "tuist.Command"),
            .product(name: "FileSystem", package: "tuist.FileSystem"),
            .product(name: "Path", package: "tuist.Path"),
            .product(name: "XcodeProj", package: "tuist.XcodeProj"),
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .testTarget(
        name: "XcodeGraphTests",
        dependencies: [.target(name: "XcodeGraph")],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
        ]
    ),
    .testTarget(
        name: "XcodeGraphMapperTests",
        dependencies: [
            "XcodeGraphMapper",
            .product(name: "FileSystem", package: "tuist.FileSystem"),
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
]

let package = Package(
    name: "XcodeGraph",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "XcodeGraph",
            targets: ["XcodeGraph"]
        ),
        .library(name: "XcodeMetadata", targets: ["XcodeMetadata"]),
        .library(name: "XcodeGraphMapper", targets: ["XcodeGraphMapper"]),
    ],
    dependencies: [
        .package(id: "flight-school.AnyCodable", .upToNextMajor(from: "0.6.7")),
        .package(id: "tuist.Path", .upToNextMajor(from: "0.3.8")),
        .package(id: "tuist.XcodeProj", .upToNextMajor(from: "9.9.0")),
        .package(id: "tuist.Command", from: "0.13.0"),
        .package(id: "tuist.FileSystem", .upToNextMajor(from: "0.15.0")),
        .package(id: "kolos65.Mockable", .upToNextMajor(from: "0.6.1")),
        .package(id: "p-x9.MachOKit", .upToNextMajor(from: "0.46.1")),
        .package(id: "swiftlang.swift-docc-plugin", from: "1.4.6"),
    ],
    targets: targets
)
