// swift-tools-version:5.2.0

import PackageDescription

let signalsDependency: Target.Dependency = .byName(name: "Signals")
let rxSwiftDependency: Target.Dependency = .product(name: "RxSwift", package: "RxSwift")
let rxBlockingDependency: Target.Dependency = .product(name: "RxBlocking", package: "RxSwift")
let rxRelayDependency: Target.Dependency = .product(name: "RxRelay", package: "RxSwift")
let rxTestDependency: Target.Dependency = .product(name: "RxTest", package: "RxSwift")
let swiftToolsSupportDependency: Target.Dependency = .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "swift-log")
let argumentParserDependency: Target.Dependency = .product(name: "ArgumentParser", package: "swift-argument-parser")
let swiftGenKitDependency: Target.Dependency = .product(name: "SwiftGenKit", package: "SwiftGen")
let swifterDependency: Target.Dependency = .byName(name: "Swifter")
let combineExtDependency: Target.Dependency = .byName(name: "CombineExt")

let package = Package(
    name: "tuist",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "tuist", targets: ["tuist"]),
        .executable(name: "tuistenv", targets: ["tuistenv"]),
        .library(name: "ProjectDescription",
                 type: .dynamic,
                 targets: ["ProjectDescription"]),
        .library(name: "TuistGraph",
                 targets: ["TuistGraph"]),
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
        .package(url: "https://github.com/tuist/XcodeProj.git", .upToNextMajor(from: "7.17.0")),
        .package(name: "Signals", url: "https://github.com/tuist/BlueSignals.git", .upToNextMajor(from: "1.0.21")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.1.1")),
        .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.4.0")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "1.3.3")),
        .package(url: "https://github.com/stencilproject/Stencil.git", .upToNextMajor(from: "0.14.0")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "4.1.0")),
        .package(name: "Swifter", url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .upToNextMinor(from: "0.1.12")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "0.3.1")),
        .package(url: "https://github.com/marmelroy/Zip.git", .upToNextMinor(from: "2.1.1")),
        .package(url: "https://github.com/tuist/GraphViz.git", .branch("tuist")),
        .package(url: "https://github.com/fortmarek/SwiftGen", .revision("ef8d6b186a03622cec8d228b18f0e2b3bb20b81c")),
        .package(url: "https://github.com/fortmarek/StencilSwiftKit.git", .branch("stable")),
        .package(url: "https://github.com/FabrizioBrancati/Queuer.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/CombineCommunity/CombineExt.git", .upToNextMajor(from: "1.2.0")),
    ],
    targets: [
        .target(
            name: "TuistGraph",
            dependencies: [swiftToolsSupportDependency]
        ),
        .target(
            name: "TuistGraphTesting",
            dependencies: ["TuistGraph", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistGraphTests",
            dependencies: ["TuistGraph", "TuistGraphTesting", "TuistSupportTesting", "TuistCoreTesting"]
        ),
        .target(
            name: "TuistCore",
            dependencies: [swiftToolsSupportDependency, "TuistSupport", "TuistGraph", "XcodeProj", "Checksum"]
        ),
        .target(
            name: "TuistCoreTesting",
            dependencies: ["TuistCore", "TuistSupportTesting", "TuistGraphTesting"]
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
            name: "TuistDoc",
            dependencies: [
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                signalsDependency,
                rxBlockingDependency,
            ]
        ),
        .target(
            name: "TuistDocTesting",
            dependencies: [
                "TuistDoc",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistCoreTesting",
                "TuistSupportTesting",
            ]
        ),
        .testTarget(
            name: "TuistDocTests",
            dependencies: [
                "TuistDoc",
                "TuistDocTesting",
                swiftToolsSupportDependency,
                "TuistSupportTesting",
                "TuistCore",
                "TuistCoreTesting",
                "TuistGraphTesting",
                "TuistSupport",
            ]
        ),
        .target(
            name: "TuistKit",
            dependencies: [
                "XcodeProj",
                swiftToolsSupportDependency,
                argumentParserDependency,
                "TuistSupport",
                "TuistGenerator",
                "TuistCache",
                "TuistAutomation",
                "ProjectDescription",
                signalsDependency,
                rxSwiftDependency,
                rxBlockingDependency,
                "TuistLoader",
                "TuistInsights",
                "TuistScaffold",
                "TuistSigning",
                "TuistDependencies",
                "TuistLinting",
                "TuistCloud",
                "TuistDoc",
                "GraphViz",
                "TuistMigration",
                "TuistAsyncQueue",
                "TuistAnalytics",
                "TuistPlugin",
                "TuistGraph",
            ]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: [
                "TuistKit",
                "TuistAutomation",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "ProjectDescription",
                rxBlockingDependency,
                "TuistLoaderTesting",
                "TuistCacheTesting",
                "TuistGeneratorTesting",
                "TuistScaffoldTesting",
                "TuistCloudTesting",
                "TuistAutomationTesting",
                "TuistSigningTesting",
                "TuistDependenciesTesting",
                "TuistLintingTesting",
                "TuistMigrationTesting",
                "TuistDocTesting",
                "TuistAsyncQueueTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistKitIntegrationTests",
            dependencies: [
                "TuistKit",
                "TuistCoreTesting",
                "TuistSupportTesting",
                "ProjectDescription",
                rxBlockingDependency,
                "TuistLoaderTesting",
                "TuistCloudTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "tuist",
            dependencies: [
                "TuistKit",
                "ProjectDescription",
            ]
        ),
        .target(
            name: "TuistEnvKit",
            dependencies: [
                argumentParserDependency,
                swiftToolsSupportDependency,
                "TuistSupport",
                rxSwiftDependency,
                rxBlockingDependency,
            ]
        ),
        .testTarget(
            name: "TuistEnvKitTests",
            dependencies: [
                "TuistEnvKit",
                "TuistSupportTesting",
            ]
        ),
        .target(
            name: "tuistenv",
            dependencies: [
                "TuistEnvKit",
            ]
        ),
        .target(
            name: "ProjectDescription",
            dependencies: []
        ),
        .testTarget(
            name: "ProjectDescriptionTests",
            dependencies: [
                "ProjectDescription",
                "TuistSupportTesting",
            ]
        ),
        .target(
            name: "TuistSupport",
            dependencies: [
                combineExtDependency,
                swiftToolsSupportDependency,
                rxSwiftDependency,
                rxRelayDependency,
                loggingDependency,
                "KeychainAccess",
                swifterDependency,
                signalsDependency,
                "Zip",
                "Checksum",
            ]
        ),
        .target(
            name: "TuistSupportTesting",
            dependencies: [
                "TuistSupport",
                swiftToolsSupportDependency,
            ]
        ),
        .testTarget(
            name: "TuistSupportTests",
            dependencies: [
                "TuistSupport",
                "TuistSupportTesting",
                rxBlockingDependency,
            ]
        ),
        .testTarget(
            name: "TuistSupportIntegrationTests",
            dependencies: [
                "TuistSupport",
                "TuistSupportTesting",
                rxBlockingDependency,
            ]
        ),
        .target(
            name: "TuistGenerator",
            dependencies: [
                "XcodeProj",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                rxBlockingDependency,
                "GraphViz",
                swiftGenKitDependency,
                "StencilSwiftKit",
            ]
        ),
        .target(
            name: "TuistGeneratorTesting",
            dependencies: [
                "TuistGenerator",
                "TuistCoreTesting",
                "TuistSupportTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistGeneratorTests",
            dependencies: [
                "TuistGenerator",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistGeneratorTesting",
                "TuistSigningTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistGeneratorIntegrationTests",
            dependencies: [
                "TuistGenerator",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistGeneratorTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistCache",
            dependencies: [
                "XcodeProj",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                rxSwiftDependency,
            ]
        ),
        .testTarget(
            name: "TuistCacheTests",
            dependencies: [
                "TuistCache",
                "TuistSupportTesting",
                "TuistCoreTesting",
                rxBlockingDependency,
                "TuistCacheTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistCacheTesting",
            dependencies: [
                "TuistCache",
                swiftToolsSupportDependency,
                "TuistCore",
                rxTestDependency,
                rxSwiftDependency,
                "TuistSupportTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistCloud",
            dependencies: [
                "XcodeProj",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                rxSwiftDependency,
            ]
        ),
        .testTarget(
            name: "TuistCloudTests",
            dependencies: [
                "TuistCloud",
                "TuistSupportTesting",
                "TuistCoreTesting",
                rxBlockingDependency,
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistCloudTesting",
            dependencies: [
                "TuistCloud",
                swiftToolsSupportDependency,
                "TuistCore",
                rxTestDependency,
                rxSwiftDependency,
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistCacheIntegrationTests",
            dependencies: [
                "TuistCache",
                "TuistSupportTesting",
                rxBlockingDependency,
                "TuistCoreTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistScaffold",
            dependencies: [
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                "StencilSwiftKit",
                "Stencil",
            ]
        ),
        .target(
            name: "TuistScaffoldTesting",
            dependencies: [
                "TuistScaffold",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistScaffoldTests",
            dependencies: [
                "TuistScaffold",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistScaffoldIntegrationTests",
            dependencies: [
                "TuistScaffold",
                "TuistSupportTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistAutomation",
            dependencies: [
                "XcodeProj",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
            ]
        ),
        .testTarget(
            name: "TuistAutomationTests",
            dependencies: [
                "TuistAutomation",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistGraphTesting",
                rxBlockingDependency,
            ]
        ),
        .target(
            name: "TuistAutomationTesting",
            dependencies: [
                "TuistAutomation",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistCoreTesting",
                "ProjectDescription",
                "TuistSupportTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistAutomationIntegrationTests",
            dependencies: [
                "TuistAutomation",
                "TuistSupportTesting",
                "TuistGraphTesting",
                rxBlockingDependency,
            ]
        ),
        .target(
            name: "TuistInsights",
            dependencies: [
                "XcodeProj",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
            ]
        ),
        .testTarget(
            name: "TuistInsightsTests",
            dependencies: [
                "TuistInsights",
                "TuistSupportTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistInsightsIntegrationTests",
            dependencies: [
                "TuistInsights",
                "TuistSupportTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistSigning",
            dependencies: [
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                "CryptoSwift",
            ]
        ),
        .target(
            name: "TuistSigningTesting",
            dependencies: [
                "TuistSigning",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistSigningTests",
            dependencies: [
                "TuistSigning",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistSigningTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistSigningIntegrationTests",
            dependencies: [
                "TuistSigning",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistSigningTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistDependencies",
            dependencies: ["TuistCore",
                           "TuistGraph",
                           "TuistSupport"]
        ),
        .target(
            name: "TuistDependenciesTesting",
            dependencies: [
                "TuistDependencies",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistDependenciesTests",
            dependencies: [
                "TuistDependencies",
                "TuistDependenciesTesting",
                "TuistCoreTesting",
                "TuistSupportTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistLinting",
            dependencies: [
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                signalsDependency,
                rxSwiftDependency,
                rxBlockingDependency,
            ]
        ),
        .target(
            name: "TuistLintingTesting",
            dependencies: [
                "TuistLinting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistLintingTests",
            dependencies: [
                "TuistLinting",
                "TuistLintingTesting",
                "TuistCoreTesting",
                "TuistSupportTesting",
                "TuistGraphTesting",
                rxBlockingDependency,
            ]
        ),
        .target(
            name: "TuistMigration",
            dependencies: [
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                "XcodeProj",
                swiftToolsSupportDependency,
            ]
        ),
        .target(
            name: "TuistMigrationTesting",
            dependencies: [
                "TuistMigration",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistMigrationTests",
            dependencies: [
                "TuistMigration",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistMigrationTesting",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistMigrationIntegrationTests",
            dependencies: [
                "TuistMigration",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistMigrationTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistAsyncQueue",
            dependencies: [
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                "XcodeProj",
                swiftToolsSupportDependency,
                "Queuer",
            ]
        ),
        .target(
            name: "TuistAsyncQueueTesting",
            dependencies: [
                "TuistAsyncQueue",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistAsyncQueueTests",
            dependencies: [
                "TuistAsyncQueue",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistAsyncQueueTesting",
                "TuistGraphTesting",
                rxBlockingDependency,
            ]
        ),
        .target(
            name: "TuistLoader",
            dependencies: [
                "XcodeProj",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                "ProjectDescription",
            ]
        ),
        .target(
            name: "TuistLoaderTesting",
            dependencies: [
                "TuistLoader",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraphTesting",
                "ProjectDescription",
                "TuistSupportTesting",
            ]
        ),
        .testTarget(
            name: "TuistLoaderTests",
            dependencies: [
                "TuistLoader",
                "TuistGraphTesting",
                "TuistSupportTesting",
                "TuistLoaderTesting",
                "TuistCoreTesting",
                rxBlockingDependency,
            ]
        ),
        .testTarget(
            name: "TuistLoaderIntegrationTests",
            dependencies: [
                "TuistLoader",
                "TuistGraphTesting",
                "TuistSupportTesting",
                "ProjectDescription",
                rxBlockingDependency,
            ]
        ),
        .testTarget(
            name: "TuistIntegrationTests",
            dependencies: [
                "TuistGenerator",
                "TuistSupportTesting",
                "TuistSupport",
                "TuistCoreTesting",
                "TuistGraphTesting",
                "TuistLoaderTesting",
            ]
        ),
        .target(
            name: "TuistAnalytics",
            dependencies: [
                "TuistAsyncQueue",
                "TuistCore",
            ]
        ),
        .testTarget(
            name: "TuistAnalyticsTests",
            dependencies: [
                "TuistSupportTesting",
                "TuistGraphTesting",
                "TuistCoreTesting",
                "XcodeProj",
            ]
        ),
        .target(
            name: "TuistPlugin",
            dependencies: [
                "TuistCore",
                "TuistGraph",
                "TuistLoader",
                "TuistSupport",
                swiftToolsSupportDependency,
            ]
        ),
        .testTarget(
            name: "TuistPluginTests",
            dependencies: [
                "TuistCore",
                "TuistLoader",
                "TuistLoaderTesting",
                "TuistGraphTesting",
                "TuistPlugin",
                "TuistSupport",
                "TuistSupportTesting",
                rxBlockingDependency,
                swiftToolsSupportDependency,
            ]
        ),
    ]
)
