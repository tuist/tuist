// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XCActivityLogNIF",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "XCActivityLogNIF",
            type: .dynamic,
            targets: ["XCActivityLogNIF"]
        ),
        .library(
            name: "XCActivityLogParser",
            targets: ["XCActivityLogParser"]
        ),
    ],
    dependencies: [
        .package(id: "MobileNativeFoundation.XCLogParser", from: "0.2.46"),
        .package(id: "tuist.Path", from: "0.3.8"),
        .package(id: "tuist.FileSystem", from: "0.15.0"),
        .package(id: "stephencelis.SQLite_swift", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "XCActivityLogParser",
            dependencies: [
                .product(name: "XCLogParser", package: "MobileNativeFoundation.XCLogParser"),
                .product(name: "Path", package: "tuist.Path"),
                .product(name: "FileSystem", package: "tuist.FileSystem"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .target(
            name: "XCActivityLogNIF",
            dependencies: [
                "XCActivityLogParser",
            ]
        ),
        .testTarget(
            name: "XCActivityLogParserTests",
            dependencies: ["XCActivityLogParser"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
