// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "B",
    products: [
        .library(name: "B", targets: ["B"]),
    ],
    targets: [
        .target(name: "B"),
    ]
)
