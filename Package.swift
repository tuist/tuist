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
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "7.17.0")),
        .package(url: "https://github.com/IBM-Swift/BlueSignals", .upToNextMajor(from: "1.0.21")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.1.1")),
        .package(url: "https://github.com/rnine/Checksum.git", .upToNextMajor(from: "1.0.2")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.4.0")),
        .package(url: "https://github.com/thii/xcbeautify.git", .upToNextMajor(from: "0.8.1")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .upToNextMajor(from: "1.3.0")),
        .package(url: "https://github.com/stencilproject/Stencil.git", .upToNextMajor(from: "0.14.0")),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", .upToNextMajor(from: "4.1.0")),
        .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
        .package(url: "https://github.com/apple/swift-tools-support-core", .upToNextMinor(from: "0.1.12")),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "0.3.1")),
        .package(url: "https://github.com/marmelroy/Zip.git", .upToNextMinor(from: "2.1.1")),
        .package(url: "https://github.com/tuist/GraphViz.git", .branch("tuist")),
        .package(url: "https://github.com/fortmarek/SwiftGen", .branch("stable")),
        .package(url: "https://github.com/fortmarek/StencilSwiftKit.git", .branch("stable")),
        .package(url: "https://github.com/FabrizioBrancati/Queuer.git", .upToNextMajor(from: "2.0.0")),
    ],
    targets: [
        .target(
            name: "TuistCore",
            dependencies: ["SwiftToolsSupport-auto", "TuistSupport", "XcodeProj", "Checksum"]
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
            name: "TuistDoc",
            dependencies: ["SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "Signals", "RxBlocking"]
        ),
        .target(
            name: "TuistDocTesting",
            dependencies: ["TuistDoc", "SwiftToolsSupport-auto", "TuistCore", "TuistCoreTesting", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistDocTests",
            dependencies: ["TuistDoc", "TuistDocTesting", "SwiftToolsSupport-auto", "TuistSupportTesting", "TuistCore", "TuistCoreTesting", "TuistSupport"]
        ),
        .target(
            name: "TuistKit",
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "ArgumentParser", "TuistSupport", "TuistGenerator", "TuistCache", "TuistAutomation", "ProjectDescription", "Signals", "RxSwift", "RxBlocking", "TuistLoader", "TuistInsights", "TuistScaffold", "TuistSigning", "TuistDependencies", "TuistCloud", "TuistDoc", "GraphViz", "TuistMigration", "TuistAsyncQueue"]
        ),
        .testTarget(
            name: "TuistKitTests",
            dependencies: ["TuistKit", "TuistAutomation", "TuistSupportTesting", "TuistCoreTesting", "ProjectDescription", "RxBlocking", "TuistLoaderTesting", "TuistCacheTesting", "TuistGeneratorTesting", "TuistScaffoldTesting", "TuistCloudTesting", "TuistAutomationTesting", "TuistSigningTesting", "TuistDependenciesTesting", "TuistMigrationTesting", "TuistDocTesting", "TuistAsyncQueueTesting"]
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
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "RxBlocking", "GraphViz", "SwiftGenKit", "StencilSwiftKit"]
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
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "RxSwift"]
        ),
        .testTarget(
            name: "TuistCacheTests",
            dependencies: ["TuistCache", "TuistSupportTesting", "TuistCoreTesting", "RxBlocking", "TuistCacheTesting"]
        ),
        .target(
            name: "TuistCacheTesting",
            dependencies: ["TuistCache", "SwiftToolsSupport-auto", "TuistCore", "RxTest", "RxSwift", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistCloud",
            dependencies: ["XcodeProj", "SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "RxSwift"]
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
            dependencies: ["SwiftToolsSupport-auto", "TuistCore", "TuistSupport", "StencilSwiftKit", "Stencil"]
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
            name: "TuistDependencies",
            dependencies: ["TuistCore", "TuistSupport"]
        ),
        .target(
            name: "TuistDependenciesTesting",
            dependencies: ["TuistDependencies"]
        ),
        .testTarget(
            name: "TuistDependenciesTests",
            dependencies: ["TuistDependencies", "TuistDependenciesTesting", "TuistCoreTesting", "TuistSupportTesting"]
        ),
        .testTarget(
            name: "TuistDependenciesIntegrationTests",
            dependencies: ["TuistDependencies", "TuistDependenciesTesting", "TuistCoreTesting", "TuistSupportTesting"]
        ),
        .target(
            name: "TuistMigration",
            dependencies: ["TuistCore", "TuistSupport", "XcodeProj", "SwiftToolsSupport-auto"]
        ),
        .target(
            name: "TuistMigrationTesting",
            dependencies: ["TuistMigration"]
        ),
        .testTarget(
            name: "TuistMigrationTests",
            dependencies: ["TuistMigration", "TuistSupportTesting", "TuistCoreTesting", "TuistMigrationTesting"]
        ),
        .testTarget(
            name: "TuistMigrationIntegrationTests",
            dependencies: ["TuistMigration", "TuistSupportTesting", "TuistCoreTesting", "TuistMigrationTesting"]
        ),
        .target(
            name: "TuistAsyncQueue",
            dependencies: ["TuistCore", "TuistSupport", "XcodeProj", "SwiftToolsSupport-auto", "Queuer"]
        ),
        .target(
            name: "TuistAsyncQueueTesting",
            dependencies: ["TuistAsyncQueue"]
        ),
        .testTarget(
            name: "TuistAsyncQueueTests",
            dependencies: ["TuistAsyncQueue", "TuistSupportTesting", "TuistCoreTesting", "TuistAsyncQueueTesting", "RxBlocking"]
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
