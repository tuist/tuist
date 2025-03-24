// swift-tools-version: 6.0
@preconcurrency import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/exponea/exponea-ios-sdk", .upToNextMajor(from: "3.1.0")),
    ]
)
