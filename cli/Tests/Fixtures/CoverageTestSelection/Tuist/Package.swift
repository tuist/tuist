// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shop",
    dependencies: [
        .package(url: "https://github.com/tuist/TestCoverageAttribution", .upToNextMinor(from: "0.3.0")),
    ]
)
