// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Proto",
    products: [
        .library(name: "Proto", targets: ["Proto"]),
    ],
    targets: [
        .target(name: "Proto"),
    ]
)
