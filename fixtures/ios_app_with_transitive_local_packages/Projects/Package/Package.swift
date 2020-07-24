// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Package",
    products: [
        .library(
            name: "Library",
            targets: ["Library"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Library",
            dependencies: []),
    ]
)
