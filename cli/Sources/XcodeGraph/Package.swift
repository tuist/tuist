// swift-tools-version:5.10
import PackageDescription

let targets: [Target] = [
    .target(
        name: "XcodeGraph",
        dependencies: [
            .product(name: "AnyCodable", package: "anycodable"),
            .product(name: "Path", package: "path"),
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
        ]
    ),
    .target(
        name: "XcodeMetadata",
        dependencies: [
            .product(name: "FileSystem", package: "filesystem"),
            .product(name: "Mockable", package: "mockable"),
            .product(name: "MachOKitC", package: "machokit"),
            "XcodeGraph",
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency"),
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "XcodeGraphMapper",
        dependencies: [
            "XcodeGraph",
            "XcodeMetadata",
            .product(name: "Command", package: "command"),
            .product(name: "FileSystem", package: "filesystem"),
            .product(name: "Path", package: "path"),
            .product(name: "XcodeProj", package: "xcodeproj"),
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
        .package(url: "https://github.com/Flight-School/AnyCodable", .upToNextMajor(from: "0.6.7")),
        .package(url: "https://github.com/tuist/Path", .upToNextMajor(from: "0.3.8")),
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "9.9.0")),
        .package(url: "https://github.com/tuist/Command", from: "0.13.0"),
        .package(url: "https://github.com/tuist/FileSystem", .upToNextMajor(from: "0.16.2")),
        .package(url: "https://github.com/Kolos65/Mockable", .upToNextMajor(from: "0.6.1")),
        .package(url: "https://github.com/p-x9/MachOKit", .upToNextMajor(from: "0.46.1")),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.6"),
    ],
    targets: targets
)
