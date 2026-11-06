// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResourcesPackage",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "ResourcesLib", targets: ["ResourcesLib"]),
    ],
    targets: [
        .target(
            name: "ResourcesLib",
            resources: [.process("greeting.txt")]
        ),
    ]
)
