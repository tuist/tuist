// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XCResultNIF",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "XCResultNIF",
            type: .dynamic,
            targets: ["XCResultNIF"]
        ),
        .library(
            name: "XCResultParser",
            targets: ["XCResultParser"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/Path", from: "0.3.8"),
        .package(url: "https://github.com/tuist/FileSystem", .upToNextMajor(from: "0.16.2")),
        .package(url: "https://github.com/tuist/Command", from: "0.12.0"),
        .package(url: "https://github.com/Kolos65/Mockable", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "XCResultParser",
            dependencies: [
                .product(name: "Path", package: "path"),
                .product(name: "FileSystem", package: "filesystem"),
                .product(name: "Command", package: "command"),
                .product(name: "Mockable", package: "mockable"),
            ],
            swiftSettings: [
                .define("MOCKING", .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "XCResultNIF",
            dependencies: [
                "XCResultParser",
                .product(name: "Path", package: "path"),
            ]
        ),
        .testTarget(
            name: "XCResultParserTests",
            dependencies: ["XCResultParser"],
            resources: [.copy("../Fixtures")]
        ),
    ]
)
