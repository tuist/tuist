// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TuistSDK",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "TuistSDK",
            targets: ["TuistSDK"]
        ),
    ],
    targets: [
        .target(
            name: "TuistSDK",
            path: "."
        ),
    ]
)
