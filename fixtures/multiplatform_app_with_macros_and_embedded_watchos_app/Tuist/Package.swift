// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.3.0"),
    ]
)
