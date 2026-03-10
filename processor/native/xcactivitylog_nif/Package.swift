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
    ],
    targets: [
        .target(
            name: "XCActivityLogParser",
            dependencies: [
                .product(name: "XCLogParser", package: "MobileNativeFoundation.XCLogParser"),
            ]
        ),
        .target(
            name: "XCActivityLogNIF",
            dependencies: [
                "XCActivityLogParser",
            ]
        ),
    ]
)
