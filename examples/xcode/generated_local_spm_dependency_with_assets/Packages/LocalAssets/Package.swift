// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalAssets",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "LocalAssets", targets: ["LocalAssets"]),
    ],
    targets: [
        .target(
            name: "LocalAssets",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
