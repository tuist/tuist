// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiPlatformAppWithSwiftMacros",
    dependencies: [
        .package(url: "https://github.com/alschmut/StructBuilderMacro", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMinor(from: "1.5.0")),
    ]
)
