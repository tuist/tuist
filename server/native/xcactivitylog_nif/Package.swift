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
        .library(
            name: "CASAnalyticsDatabase",
            targets: ["CASAnalyticsDatabase"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MobileNativeFoundation/XCLogParser", from: "0.2.47"),
        .package(url: "https://github.com/tuist/Path", from: "0.3.8"),
        .package(url: "https://github.com/tuist/FileSystem", .upToNextMajor(from: "0.16.2")),
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "CASAnalyticsDatabase",
            dependencies: [
                .product(name: "SQLite", package: "sqlite.swift"),
            ]
        ),
        .target(
            name: "XCActivityLogParser",
            dependencies: [
                "CASAnalyticsDatabase",
                .product(name: "XCLogParser", package: "xclogparser"),
                .product(name: "Path", package: "path"),
                .product(name: "FileSystem", package: "filesystem"),
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
