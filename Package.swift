// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "xpm",
    products: [
        .executable(name: "xpm", targets: ["xpm"]),
        .executable(name: "xpmembed", targets: ["xpmembed"]),
        .executable(name: "xpmenv", targets: ["xpmenv"]),
        .library(name: "ProjectDescription",
                 type: .dynamic,
                 targets: ["ProjectDescription"]),
    ],
    dependencies: [
        .package(url: "git@github.com:xcode-project-manager/xcodeproj.git", .revision("9e07138d737e88b940fbba8c503667339fe95330")),
        .package(url: "https://github.com/apple/swift-package-manager", .revision("3e71e57db41ebb32ccec1841a7e26c428a9c08c5")),
    ],
    targets: [
        .target(
            name: "xpmcore",
            dependencies: ["Utility"]),
        .target(
            name: "xpmcoreTesting",
            dependencies: ["xpmcore"]),
        .testTarget(
            name: "xpmcoreTests",
            dependencies: ["xpmcore", "xpmcoreTesting"]),
        .target(
            name: "xpmkit",
            dependencies: ["xcodeproj", "Utility", "xpmcore"]),
        .testTarget(
            name: "xpmkitTests",
            dependencies: ["xpmkit", "xpmcoreTesting"]),
        .target(
            name: "xpm",
            dependencies: ["xpmkit"]),
        .target(
            name: "xpmembed",
            dependencies: ["xpmkit"]),
        .target(
            name: "xpmenvkit",
            dependencies: ["Utility", "xpmcore"]),
        .testTarget(
            name: "xpmenvkitTests",
            dependencies: ["xpmenvkit", "xpmcoreTesting"]),
        .target(
            name: "xpmenv",
            dependencies: ["xpmenvkit"]),
        .target(
            name: "ProjectDescription",
            dependencies: []),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: ["ProjectDescription"]),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["xpmkit", "Utility"]
        ),
    ]
)
