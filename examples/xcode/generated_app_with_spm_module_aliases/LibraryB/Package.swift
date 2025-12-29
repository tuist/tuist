// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LibraryB",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "LibraryB",
            targets: ["LibraryB"]
        ),
    ],
    dependencies: [
        .package(path: "../LibraryA"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "LibraryB",
            dependencies: [
                .product(name: "LibraryA", package: "LibraryA", moduleAliases: ["Utilities": "LibraryAUtilities"]),
                .target(name: "Utilities"),
            ]
        ),
        .target(
            name: "Utilities"
        ),
    ]
)
