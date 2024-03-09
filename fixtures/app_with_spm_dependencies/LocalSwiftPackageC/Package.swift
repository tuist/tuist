// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackageC",
    products: [.library(name: "LibraryC", targets: ["LibraryC"])],
    targets: [
        .target(name: "LibraryC"),
    ]
)
