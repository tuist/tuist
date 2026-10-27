// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PackageB",
    products: [
        .library(
            name: "OtherLibrary",
            targets: ["OtherLibraryCore"]
        ),
    ],
    targets: [
        .target(
            name: "OtherLibraryCore",
            dependencies: []
        ),
    ]
)
