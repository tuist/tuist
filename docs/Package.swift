// swift-tools-version:5.7
/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Package manifest for SlothCreator.
*/

import PackageDescription

let package = Package(
    name: "tuist",
    products: [
        .executable(
            name: "tuist",
            targets: ["tuist"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "tuist"
        )
    ]
)
