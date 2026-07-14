// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TestSupportPackage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    targets: [
        .target(name: "TestSupport"),
    ]
)
