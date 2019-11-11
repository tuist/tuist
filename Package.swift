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
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "7.4.0")),
        .package(url: "https://github.com/apple/swift-package-manager", .upToNextMajor(from: "0.5.0")),
    ],
    targets: [
        .target(
            name: "TuistKit",
            dependencies: ["XcodeProj", "SPMUtility", "TuistSupport", "TuistGenerator", "ProjectDescription"]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistSupportTesting", "ProjectDescription"]
        ),
        .testTarget(
            name: "TuistKitIntegrationTests",
            dependencies: ["TuistKit", "TuistSupportTesting", "ProjectDescription"]
        ),
        .target(
            name: "tuist",
            dependencies: ["TuistKit"]
        ),
        .target(
            name: "TuistEnvKit",
            dependencies: ["SPMUtility", "TuistSupport"]
        ),
        .testTarget(
            name: "TuistEnvKitTests",
            dependencies: ["TuistEnvKit", "TuistSupportTesting"]
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
            dependencies: ["ProjectDescription", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistSupport",
            dependencies: ["SPMUtility"]
        ),
        .target(
            name: "TuistSupportTesting",
            dependencies: ["TuistSupport", "SPMUtility"]
        ),
        .testTarget(
            name: "TuistSupportTests",
            dependencies: ["TuistSupport", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistGenerator",
            dependencies: ["XcodeProj", "SPMUtility", "TuistSupport"]
        ),
        .testTarget(
            name: "TuistGeneratorTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistGeneratorIntegrationTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistIntegrationTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting"]
        ),
    ]
)
