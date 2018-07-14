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
        .package(url: "git@github.com:xcode-project-manager/xcodeproj.git", .revision("7ff584c3a0114eac59e5cc711f96c921a6c3b26e")),
        .package(url: "https://github.com/apple/swift-package-manager", from: "0.2.0"),
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
            dependencies: ["xpmcore"]),
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
            dependencies: ["xpm", "xpmcoreTesting"]),
        .target(
            name: "xpmenv",
            dependencies: ["xpmenvkit"]),
        .target(
            name: "ProjectDescription",
            dependencies: []),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: ["ProjectDescription"]),
        .target(
            name: "xpmtools",
            dependencies: ["Utility", "xpmcore"]),
        .testTarget(
            name: "xpmtoolsTests",
            dependencies: ["xpmtools"]),
    ]
)
