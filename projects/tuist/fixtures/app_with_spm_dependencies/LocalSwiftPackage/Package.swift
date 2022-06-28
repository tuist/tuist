// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [.library(name: "Styles", targets: ["Styles"])],
    targets: [
        .target(name: "Styles", resources: [.process("Resources/Fonts")]),
        .testTarget(name: "StylesTests", dependencies: ["Styles"]),
    ]
)
