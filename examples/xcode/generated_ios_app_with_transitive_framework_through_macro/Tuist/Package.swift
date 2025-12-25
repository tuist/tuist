// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/JaroVoltix/SwiftAndTipsMacros", exact: "1.0.3"),
    ]
)
