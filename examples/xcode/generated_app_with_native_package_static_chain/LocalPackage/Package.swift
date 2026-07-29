// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalPackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PackageFeature", targets: ["PackageFeature"]),
    ],
    targets: [
        .target(
            name: "CModule",
            publicHeadersPath: "include"
        ),
        .target(
            name: "PackageFeature",
            dependencies: ["CModule"]
        ),
    ]
)
