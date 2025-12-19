// swift-tools-version: 6.0
@preconcurrency import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios", .upToNextMajor(from: "5.0.0")),
    ]
)
