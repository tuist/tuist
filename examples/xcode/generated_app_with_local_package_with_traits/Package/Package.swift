// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Package",
    platforms: [.iOS("18.0"), .macOS("15.7")],
    products: [
        .library(
            name: "Package",
            targets: ["Package"]
        )
    ],
    traits: [
        .default(enabledTraits: ["Tuist"]),
        .trait(name: "Tuist"),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-configuration", .upToNextMajor(from: "1.0.0"),
            traits: [.defaults, "JSON"])
    ],
    targets: [
        .target(
            name: "Package",
            dependencies: [
                .product(name: "Configuration", package: "swift-configuration")
            ]
        )
    ],
)
