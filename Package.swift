// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "tuist",
    platforms: [.macOS(.v10_12)],
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
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "7.11.0")),
        .package(url: "https://github.com/IBM-Swift/BlueSignals", .upToNextMajor(from: "1.0.21")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.0.1")),
        .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/thii/xcbeautify.git", .upToNextMajor(from: "0.8.0")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .upToNextMajor(from: "1.3.0")),
        .package(url: "https://github.com/stencilproject/Stencil", .branch("master")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "4.1.0")),
        .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.4.7")),
        .package(url: "https://github.com/apple/swift-tools-support-core", .upToNextMinor(from: "0.1.1")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "0.0.6")),
        .package(url: "https://github.com/marmelroy/Zip.git", .upToNextMinor(from: "2.0.0")),
        .package(url: "https://github.com/SwiftDocOrg/GraphViz/", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "TuistCore",
            dependencies: ["SwiftToolsSupport-auto", "TuistSupport", "XcodeProj"]
        ),
        .target(
            name: "TuistCoreTesting",
            dependencies: ["TuistCore", "TuistSupportTesting"]
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
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "ArgumentParser", "TuistSupport", "TuistGenerator", "TuistCache", "TuistAutomation", "ProjectDescription", "Signals", "RxSwift", "RxBlocking", "Checksum", "TuistLoader", "TuistInsights", "TuistScaffold", "TuistSigning", "TuistCloud", "GraphViz"]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistAutomation", "TuistSupportTesting", "TuistCoreTesting", "ProjectDescription", "RxBlocking", "TuistLoaderTesting", "TuistCacheTesting", "TuistGeneratorTesting", "TuistScaffoldTesting", "TuistCloudTesting", "TuistAutomationTesting", "TuistSigningTesting"]
        ),
        .testTarget(
            name: "TuistKitIntegrationTests",
            dependencies: ["TuistKit", "TuistCoreTesting", "TuistSupportTesting", "ProjectDescription", "RxBlocking", "TuistLoaderTesting", "TuistCloudTesting"]
        ),
        .target(
            name: "tuist",
            dependencies: ["TuistKit", "ProjectDescription"]
        ),
        .target(
            name: "TuistEnvKit",
            dependencies: ["ArgumentParser", "SwiftToolsSupport-auto", "TuistSupport", "RxSwift", "RxBlocking"]
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
            dependencies: ["SwiftToolsSupport-auto", "RxSwift", "RxRelay", "Logging", "KeychainAccess", "Swifter", "Signals", "Zip"]
        ),
        .target(
            name: "TuistSupportTesting",
            dependencies: ["TuistSupport", "SwiftToolsSupport-auto"]
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
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "RxBlocking", "GraphViz"]
        ),
        .target(
            name: "TuistGeneratorTesting",
            dependencies: ["TuistGenerator", "TuistCoreTesting", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistGeneratorTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting", "TuistCoreTesting", "TuistGeneratorTesting", "TuistSigningTesting"]
        ),
        .testTarget(
            name: "TuistGeneratorIntegrationTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting", "TuistCoreTesting", "TuistGeneratorTesting"]
        ),
        .target(
            name: "TuistCache",
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "Checksum", "RxSwift"]
        ),
        .testTarget(
            name: "TuistCacheTests",
            dependencies: ["TuistCache", "TuistSupportTesting", "TuistCoreTesting", "RxBlocking", "TuistCacheTesting"]
        ),
        .target(
            name: "TuistCacheTesting",
            dependencies: ["TuistCache", "SwiftToolsSupport-auto", "TuistCore", "RxTest", "RxSwift"]
        ),
        .target(
            name: "TuistCloud",
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "Checksum", "RxSwift"]
        ),
        .testTarget(
            name: "TuistCloudTests",
            dependencies: ["TuistCloud", "TuistSupportTesting", "TuistCoreTesting", "RxBlocking"]
        ),
        .target(
            name: "TuistCloudTesting",
            dependencies: ["TuistCloud", "SwiftToolsSupport-auto", "TuistCore", "RxTest", "RxSwift"]
        ),
        .testTarget(
            name: "TuistCacheIntegrationTests",
            dependencies: ["TuistCache", "TuistSupportTesting", "RxBlocking", "TuistCoreTesting"]
        ),
        .target(
            name: "TuistScaffold",
            dependencies: ["SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "Stencil"]
        ),
        .target(
            name: "TuistScaffoldTesting",
            dependencies: ["TuistScaffold"]
        ),
        .testTarget(
            name: "TuistScaffoldTests",
            dependencies: ["TuistScaffold", "TuistSupportTesting", "TuistCoreTesting"]
        ),
        .testTarget(
            name: "TuistScaffoldIntegrationTests",
            dependencies: ["TuistScaffold", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistAutomation",
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "XcbeautifyLib"]
        ),
        .testTarget(
            name: "TuistAutomationTests",
            dependencies: ["TuistAutomation", "TuistSupportTesting", "TuistCoreTesting", "RxBlocking"]
        ),
        .target(
            name: "TuistAutomationTesting",
            dependencies: ["TuistAutomation", "SwiftToolsSupport-auto", "TuistCore", "TuistCoreTesting", "ProjectDescription", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistAutomationIntegrationTests",
            dependencies: ["TuistAutomation", "TuistSupportTesting", "RxBlocking"]
        ),
        .target(
            name: "TuistInsights",
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "XcbeautifyLib"]
        ),
        .testTarget(
            name: "TuistInsightsTests",
            dependencies: ["TuistInsights", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistInsightsIntegrationTests",
            dependencies: ["TuistInsights", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistSigning",
            dependencies: ["TuistCore", "TuistSupport", "CryptoSwift"]
        ),
        .target(
            name: "TuistSigningTesting",
            dependencies: ["TuistSigning"]
        ),
        .testTarget(
            name: "TuistSigningTests",
            dependencies: ["TuistSigning", "TuistSupportTesting", "TuistCoreTesting", "TuistSigningTesting"]
        ),
        .testTarget(
            name: "TuistSigningIntegrationTests",
            dependencies: ["TuistSigning", "TuistSupportTesting", "TuistCoreTesting", "TuistSigningTesting"]
        ),
        .target(
            name: "TuistLoader",
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "ProjectDescription"]
        ),
        .target(
            name: "TuistLoaderTesting",
            dependencies: ["TuistLoader", "SwiftToolsSupport-auto", "TuistCore", "ProjectDescription", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistLoaderTests",
            dependencies: ["TuistLoader", "TuistSupportTesting", "TuistLoaderTesting", "TuistCoreTesting", "RxBlocking"]
        ),
        .testTarget(
            name: "TuistLoaderIntegrationTests",
            dependencies: ["TuistLoader", "TuistSupportTesting", "ProjectDescription", "RxBlocking"]
        ),
        .testTarget(
            name: "TuistIntegrationTests",
            dependencies: ["TuistGenerator", "TuistSupportTesting", "TuistSupport", "TuistCoreTesting", "TuistLoaderTesting"]
        ),
    ]
)
