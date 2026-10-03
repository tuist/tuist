// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TestSupportCorePackage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TestSupportCore", targets: ["TestSupportCore"]),
    ],
    targets: [
        .target(name: "TestSupportCore", dependencies: ["TestSupportUtilities"]),
        .target(name: "TestSupportUtilities"),
    ]
)
