// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/realm/realm-swift", .exact("20.0.3")),
    ]
)
