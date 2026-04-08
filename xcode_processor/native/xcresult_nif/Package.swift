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
        .package(id: "tuist.Path", from: "0.3.8"),
        .package(id: "tuist.FileSystem", from: "0.15.0"),
        .package(id: "tuist.Command", from: "0.12.0"),
        .package(id: "kolos65.Mockable", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "XCResultParser",
            dependencies: [
                .product(name: "Path", package: "tuist.Path"),
                .product(name: "FileSystem", package: "tuist.FileSystem"),
                .product(name: "Command", package: "tuist.Command"),
                .product(name: "Mockable", package: "kolos65.Mockable"),
            ],
            swiftSettings: [
                .define("MOCKING", .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "XCResultNIF",
            dependencies: [
                "XCResultParser",
                .product(name: "Path", package: "tuist.Path"),
            ]
        ),
        .testTarget(
            name: "XCResultParserTests",
            dependencies: ["XCResultParser"],
            resources: [.copy("../Fixtures")]
        ),
    ]
)
