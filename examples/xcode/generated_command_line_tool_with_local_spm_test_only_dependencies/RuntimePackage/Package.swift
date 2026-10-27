// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RuntimePackage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RuntimeLib", targets: ["RuntimeLib"]),
    ],
    dependencies: [
        .package(path: "../TestSupportPackage"),
    ],
    targets: [
        .target(name: "RuntimeLib"),
        .testTarget(
            name: "RuntimeLibTests",
            dependencies: [
                "RuntimeLib",
                .product(name: "TestSupport", package: "TestSupportPackage"),
            ]
        ),
    ]
)
