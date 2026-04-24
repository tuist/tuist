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
        .package(id: "MobileNativeFoundation.XCLogParser", from: "0.2.47"),
        .package(id: "tuist.Path", from: "0.3.8"),
        .package(id: "tuist.FileSystem", .upToNextMajor(from: "0.16.2")),
        .package(id: "stephencelis.SQLite_swift", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "CASAnalyticsDatabase",
            dependencies: [
                .product(name: "SQLite", package: "stephencelis.SQLite_swift"),
            ]
        ),
        .target(
            name: "XCActivityLogParser",
            dependencies: [
                "CASAnalyticsDatabase",
                .product(name: "XCLogParser", package: "MobileNativeFoundation.XCLogParser"),
                .product(name: "Path", package: "tuist.Path"),
                .product(name: "FileSystem", package: "tuist.FileSystem"),
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
