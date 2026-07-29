// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "A",
    products: [
        .library(name: "A", targets: ["A"]),
    ],
    dependencies: [
        .package(url: "../B", "0.0.8"..<"2.0.0"),
    ],
    targets: [
        .target(name: "A", dependencies: ["B"]),
    ]
)
