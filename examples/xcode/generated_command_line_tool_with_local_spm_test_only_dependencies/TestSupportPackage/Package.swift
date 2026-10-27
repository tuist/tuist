// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TestSupportPackage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TestSupport", targets: ["TestSupport"]),
    ],
    dependencies: [
        .package(path: "../TestSupportCorePackage"),
    ],
    targets: [
        .target(name: "TestSupport", dependencies: [
            .product(name: "TestSupportCore", package: "TestSupportCorePackage"),
        ]),
    ]
)
