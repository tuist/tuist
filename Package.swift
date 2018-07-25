// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "tuist",
    products: [
        .executable(name: "tuist", targets: ["tuist"]),
        .executable(name: "tuistenv", targets: ["tuistenv"]),
        .library(name: "ProjectDescription",
                 type: .dynamic,
                 targets: ["ProjectDescription"]),
    ],
    dependencies: [
        .package(url: "git@github.com:tuist/xcodeproj.git", .revision("549d67686d90ef8e45fccdca147682f185af2ad0")),
        .package(url: "git@github.com:apple/swift-package-manager.git", .revision("3e71e57db41ebb32ccec1841a7e26c428a9c08c5")),
        .package(url: "git@github.com:tuist/SwiftShell.git", .revision("b9afd2eb8cc5b0cd5713d6ed4e649948ec70ff8e")),
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
