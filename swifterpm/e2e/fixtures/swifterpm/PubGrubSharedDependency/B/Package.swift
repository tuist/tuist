// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "B",
    products: [
        .library(name: "B", targets: ["B"]),
    ],
    dependencies: [
        .package(url: "../Shared", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(name: "B", dependencies: ["Shared"]),
    ]
)
