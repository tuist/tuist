// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LocalTwo",
    products: [
        .library(name: "LocalTwo", targets: ["LocalTwo"]),
    ],
    targets: [
        .target(name: "LocalTwo"),
    ]
)
