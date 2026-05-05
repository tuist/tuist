// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    products: [
        .library(name: "LocalSwiftPackage", targets: ["LocalSwiftPackage"]),
    ],
    targets: [
        .target(
            name: "LocalSwiftPackage",
            dependencies: [],
            resources: [.embedInCode("Resources")]
        ),
    ]
)
