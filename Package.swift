// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "tuist",
    platforms: [.macOS(.v10_11)],
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
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "7.8.0")),
        .package(url: "https://github.com/apple/swift-package-manager", .upToNextMajor(from: "0.5.0")),
        .package(url: "https://github.com/IBM-Swift/BlueSignals", .upToNextMajor(from: "1.0.21")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.0.1")),
        .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
    ],
    targets: [
        .target(
            name: "TuistCore",
            dependencies: ["SPMUtility", "TuistSupport", "XcodeProj"]
        ),
        .target(
            name: "TuistCoreTesting",
            dependencies: ["TuistCore"]
        ),
        .testTarget(
            name: "TuistCoreTests",
            dependencies: ["TuistCore", "TuistCoreTesting", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistCoreIntegrationTests",
            dependencies: ["TuistCore", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistKit",
            dependencies: ["XcodeProj", "SPMUtility", "TuistSupport", "TuistGenerator", "TuistCache", "TuistAutomation", "ProjectDescription", "Signals", "RxSwift", "Checksum", "TuistLoader"]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistSupportTesting", "ProjectDescription", "RxBlocking", "Checksum", "TuistLoaderTesting"]
        ),
        .testTarget(
            name: "TuistKitIntegrationTests",
            dependencies: ["TuistKit", "TuistSupportTesting", "ProjectDescription", "RxBlocking", "Checksum", "TuistLoaderTesting"]
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
            dependencies: ["SPMUtility", "RxSwift", "RxRelay"]
        ),
        .target(
            name: "TuistSupportTesting",
            dependencies: ["TuistSupport", "SPMUtility"]
        ),
        .testTarget(
            name: "TuistSupportTests",
            dependencies: ["TuistSupport", "TuistSupportTesting", "RxBlocking"]
        ),
        .testTarget(
            name: "TuistSupportIntegrationTests",
            dependencies: ["TuistSupport", "TuistSupportTesting", "RxBlocking"]
        ),
        .target(
            name: "TuistGenerator",
            dependencies: ["XcodeProj", "SPMUtility", "TuistCore", "TuistSupport"]
        ),
        .testTarget(
            name: "TuistGeneratorTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistGeneratorIntegrationTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistCache",
            dependencies: ["XcodeProj", "SPMUtility", "TuistCore", "TuistSupport"]
        ),
        .testTarget(
            name: "TuistCacheTests",
            dependencies: ["TuistCache", "TuistSupportTesting", "TuistCoreTesting", "RxBlocking"]
        ),
        .testTarget(
            name: "TuistCacheIntegrationTests",
            dependencies: ["TuistCache", "TuistSupportTesting", "RxBlocking"]
        ),
        .target(
            name: "TuistAutomation",
            dependencies: ["XcodeProj", "SPMUtility", "TuistCore", "TuistSupport"]
        ),
        .testTarget(
            name: "TuistAutomationTests",
            dependencies: ["TuistAutomation", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistAutomationIntegrationTests",
            dependencies: ["TuistAutomation", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistLoader",
            dependencies: ["XcodeProj", "SPMUtility", "TuistCore", "TuistSupport"]
        ),
        .target(
            name: "TuistLoaderTesting",
            dependencies: ["TuistLoader", "SPMUtility", "TuistCore", "ProjectDescription"]
        ),
        .testTarget(
            name: "TuistLoaderTests",
            dependencies: ["TuistLoader", "TuistSupportTesting", "TuistLoaderTesting"]
        ),
        .testTarget(
            name: "TuistLoaderIntegrationTests",
            dependencies: ["TuistLoader", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistIntegrationTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting", "TuistSupport"]
        ),
    ]
)
