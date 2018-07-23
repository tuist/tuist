// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "tuist",
    products: [
        .executable(name: "tuist", targets: ["tuist"]),
        .executable(name: "tuist-embed", targets: ["tuist-embed"]),
        .executable(name: "tuistenv", targets: ["tuistenv"]),
        .library(name: "ProjectDescription",
                 type: .dynamic,
                 targets: ["ProjectDescription"]),
    ],
    dependencies: [
        .package(url: "git@github.com:tuist/xcodeproj.git", .revision("9e07138d737e88b940fbba8c503667339fe95330")),
        .package(url: "git@github.com:apple/swift-package-manager.git", .revision("3e71e57db41ebb32ccec1841a7e26c428a9c08c5")),
        .package(url: "git@github.com:kareman/SwiftShell.git", .revision("3f335df4d43e6794dfa1d9ee91294b02f1d94d01")),

    ],
    targets: [
        .target(
            name: "TuistCore",
            dependencies: ["Utility", "SwiftShell"]),
        .target(
            name: "TuistCoreTesting",
            dependencies: ["TuistCore"]),
        .testTarget(
            name: "TuistCoreTests",
            dependencies: ["TuistCore", "TuistCoreTesting"]),
        .target(
            name: "TuistKit",
            dependencies: ["xcodeproj", "Utility", "TuistCore"]),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistCoreTesting"]),
        .target(
            name: "tuist",
            dependencies: ["TuistKit"]),
        .target(
            name: "tuist-embed",
            dependencies: ["TuistKit"]),
        .target(
            name: "TuistEnvKit",
            dependencies: ["Utility", "TuistCore"]),
        .testTarget(
            name: "TuistEnvKitTests",
            dependencies: ["TuistEnvKit", "TuistCoreTesting"]),
        .target(
            name: "tuistenv",
            dependencies: ["TuistEnvKit"]),
        .target(
            name: "ProjectDescription",
            dependencies: []),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: ["ProjectDescription"]),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["TuistKit", "Utility"]
        ),
    ]
)
