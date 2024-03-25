// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackage",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [.library(name: "Styles", targets: ["Styles"])],
    dependencies: [
        .package(path: "../LocalSwiftPackageB"),
    ],
    targets: [
        .target(
            name: "Styles",
            dependencies: [
                .product(name: "LibraryA", package: "LocalSwiftPackageB"),
            ],
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
