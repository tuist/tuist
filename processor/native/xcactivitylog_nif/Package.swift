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
    ],
    dependencies: [
        .package(id: "MobileNativeFoundation.XCLogParser", from: "0.2.46"),
    ],
    targets: [
        .target(
            name: "XCActivityLogNIF",
            dependencies: [
                .product(name: "XCLogParser", package: "MobileNativeFoundation.XCLogParser"),
            ],
            path: "Sources/XCActivityLogNIF"
        ),
    ]
)
