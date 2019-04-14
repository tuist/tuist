// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "tuist",
    products: [
        .executable(name: "tuist", targets: ["tuist"]),
        .executable(name: "tuistenv", targets: ["tuistenv"]),
        .library(name: "ProjectDescription",
                 type: .dynamic,
                 targets: ["ProjectDescription"]),

        /// TuistGenerator
        ///
        /// A high level Xcode generator library
        /// responsible for generating Xcode projects & workspaces.
        ///
        /// This library can be used in external tools that wish to
        /// leverage Tuist's Xcode generation features.
        ///
        /// Note: This library should be treated as **unstable** as
        ///       it is still under development and may include breaking
        ///       changes in future releases.
        .library(name: "TuistGenerator",
                 targets: ["TuistGenerator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tuist/xcodeproj.git", .revision("86b5dd403c1fcf0a7325a65b6d6f10a8a3a369b9")),
        .package(url: "https://github.com/apple/swift-package-manager", .branch("swift-5.0-RELEASE")),
    ],
    targets: [
        .target(
            name: "TuistKit",
            dependencies: ["XcodeProj", "SPMUtility", "TuistCore", "TuistGenerator", "ProjectDescription"]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistCoreTesting", "ProjectDescription"]
        ),
        .target(
            name: "tuist",
            dependencies: ["TuistKit"]
        ),
        .target(
            name: "TuistEnvKit",
            dependencies: ["SPMUtility", "TuistCore"]
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
            dependencies: ["SPMUtility"]
        ),
        .target(
            name: "TuistCoreTesting",
            dependencies: ["TuistCore"]
        ),
        .testTarget(
            name: "TuistCoreTests",
            dependencies: ["TuistCore", "TuistCoreTesting"]
        ),
        .target(
            name: "TuistGenerator",
            dependencies: ["XcodeProj", "SPMUtility", "TuistCore"]
        ),
        .testTarget(
            name: "TuistGeneratorTests",
            dependencies: ["TuistGenerator", "TuistCoreTesting"]
        ),
    ]
)
