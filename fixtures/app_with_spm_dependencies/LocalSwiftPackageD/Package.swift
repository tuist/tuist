// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackageD",
    products: [.library(name: "LibraryD", targets: ["LibraryD"])],
    dependencies: [
        .package(path: "../LocalSwiftPackageC"),
    ],
    targets: [
        .target(
            name: "LibraryD",
            dependencies: ["LibraryC"]
        ),
    ]
)
