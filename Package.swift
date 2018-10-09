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
        .package(url: "https://github.com/tuist/core.git", .revision("4500863dd846244323b29cb0950cb861e1fddcd0")),
        .package(url: "https://github.com/apple/swift-package-manager", .upToNextMinor(from: "0.2.1")),
        .package(url: "https://github.com/Carthage/ReactiveTask.git", .upToNextMinor(from: "0.15.0")),
        .package(url: "https://github.com/jpsim/Yams.git", .upToNextMinor(from: "1.0.1")),
    ],
    targets: [
        .target(
            name: "TuistShared",
            dependencies: ["Utility", "TuistCore"]
        ),
        .target(
            name: "TuistSharedTesting",
            dependencies: ["TuistShared"]
        ),
        .target(
            name: "TuistKit",
            dependencies: ["xcodeproj", "Utility", "TuistCore", "Yams", "TuistShared"]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistCoreTesting", "TuistSharedTesting"]
        ),
        .target(
            name: "tuist",
            dependencies: ["TuistKit"]
        ),
        .target(
            name: "TuistEnvKit",
            dependencies: ["Utility", "TuistCore", "TuistShared", "TuistSharedTesting"]
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
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["TuistKit", "Utility"]
        ),
    ]
)
