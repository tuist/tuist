// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyPackage",
    products: [
        .executable(name: "MyCLI", targets: ["MyCLI"]),
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MyPackage",
            targets: ["MyPackage"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.8.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "MyCLI",
            dependencies: [
                "MyPackage",
            ]
        ),
        .target(
            name: "MyPackage",
            dependencies: [
                "Alamofire",
            ]
        ),
        .testTarget(
            name: "MyPackageTests",
            dependencies: ["MyPackage"]
        ),
    ]
)
