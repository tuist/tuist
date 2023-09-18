// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [.library(name: "Styles", targets: ["Styles"])],
    targets: [
        .target(
            name: "Styles",
            resources: [
                .process("Resources/Fonts"),
                .copy("Resources/jsonFile.json"), // copy rule, single file
                .copy("Resources/Playground.playground"), // copy rule, opaque file
                .copy("Resources/www"), // copy rule, directory
            ]
        ),
        .testTarget(name: "StylesTests", dependencies: ["Styles"]),
    ]
)
