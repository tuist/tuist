// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    products: [
        .library(name: "LocalSwiftPackage", targets: ["LocalSwiftPackage"]),
    ],
    targets: [
        .target(
            name: "LocalSwiftPackage"
        ),
    ]
)
