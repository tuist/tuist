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
        .package(url: "git@github.com:xcode-project-manager/xcodeproj.git", .revision("1ad8b0739963d9cc9592b9616a2f027ade7c93ab")),
        .package(url: "https://github.com/apple/swift-package-manager", from: "0.2.0"),
    ],
    targets: [
        .target(
            name: "xpmkit",
            dependencies: ["xcodeproj", "Utility"]),
        .testTarget(
            name: "xpmkitTests",
            dependencies: ["xpmkit"]),
        .target(
            name: "xpm",
            dependencies: ["xpmkit"]),
        .target(
            name: "xpmembed",
            dependencies: ["xpmkit"]),
        .target(
            name: "xpmenv",
            dependencies: ["xpmkit"]),
        .target(
            name: "ProjectDescription",
            dependencies: []),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: ["ProjectDescription"]),
        .target(
            name: "xpmtools",
            dependencies: ["Utility"]),
        .testTarget(
            name: "xpmtoolsTests",
            dependencies: ["xpmtools"]),
    ]
)
