// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    products: [
        .library(name: "LocalSwiftPackage", targets: ["LocalSwiftPackage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "LocalSwiftPackage",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
    ]
)
