// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LibraryA",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "LibraryA",
            targets: ["LibraryA"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.10.1"),
        .package(path: "../LibraryB"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "LibraryA",
            dependencies: [
                "LibraryB",
                "Alamofire",
            ]
        ),
        .testTarget(
            name: "LibraryATests",
            dependencies: ["LibraryA"]
        ),
    ]
)
