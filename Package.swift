// swift-tools-version:4.2

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
        .package(url: "https://github.com/tuist/xcodeproj.git", .upToNextMinor(from: "6.0.0")),
        .package(url: "https://github.com/apple/swift-package-manager", .upToNextMinor(from: "0.2.1")),
        .package(url: "https://github.com/jpsim/Yams.git", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/tuist/SwiftShell.git", .revision("50d8186859aedd1ce3ab404d080ab6a781591e72")),
    ],
    targets: [
        .target(
            name: "TuistKit",
            dependencies: ["xcodeproj", "Utility", "TuistCore", "Yams"]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistCoreTesting"]
        ),
        .target(
            name: "tuist",
            dependencies: ["TuistKit"]
        ),
        .target(
            name: "TuistEnvKit",
            dependencies: ["Utility", "TuistCore"]
        ),
        .testTarget(
            name: "TuistEnvKitTests",
            dependencies: ["TuistEnvKit", "TuistCoreTesting"]
        ),
        .target(
            name: "tuistenv",
            dependencies: ["TuistEnvKit"]
        ),
        .target(
            name: "ProjectDescription",
            dependencies: []
        ),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: ["ProjectDescription"]
        ),
        .target(
            name: "TuistCore",
            dependencies: ["Utility", "SwiftShell"]
        ),
        .target(
            name: "TuistCoreTesting",
            dependencies: ["TuistCore"]
        ),
        .testTarget(
            name: "TuistCoreTests",
            dependencies: ["TuistCore", "TuistCoreTesting"]
        ),
    ]
)
