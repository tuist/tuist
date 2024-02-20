// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LocalPackage",
    dependencies: [
        .package(path: "Framework")
    ]
)
