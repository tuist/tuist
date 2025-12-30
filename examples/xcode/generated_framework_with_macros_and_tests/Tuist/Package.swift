// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax", "510.0.3" ..< "601.0.0-prerelease"),
    ]
)
