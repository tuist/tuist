// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Package",
    products: [
        .library(
            name: "Package",
            targets: ["Package"]
        ),
    ],
    traits: [
        .trait(name: "Tuist"),
    ],
    targets: [
        .target(
            name: "Package"
        ),
    ]
)
