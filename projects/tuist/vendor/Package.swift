// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "tuistvendor",
    platforms: [.macOS(.v12)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.52.6"),
        .package(url: "https://github.com/realm/SwiftLint", from: "0.53.0"),
    ],
    targets: []
)
