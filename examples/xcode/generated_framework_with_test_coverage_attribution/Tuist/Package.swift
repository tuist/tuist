// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Calculator",
    dependencies: [
        .package(url: "https://github.com/tuist/TestCoverageAttribution", .upToNextMinor(from: "0.1.1")),
    ]
)
