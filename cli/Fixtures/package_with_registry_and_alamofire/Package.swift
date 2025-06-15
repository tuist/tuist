// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Library",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Library",
            targets: ["Library"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(id: "Alamofire.Alamofire", exact: "5.10.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Library",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire.Alamofire"),
            ]
        ),
    ]
)
