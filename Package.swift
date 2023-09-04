// swift-tools-version:5.7.0

import PackageDescription

let swiftToolsSupportDependency: Target.Dependency = .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "swift-log")
let argumentParserDependency: Target.Dependency = .product(name: "ArgumentParser", package: "swift-argument-parser")
let swiftGenKitDependency: Target.Dependency = .product(name: "SwiftGenKit", package: "SwiftGen")
let swifterDependency: Target.Dependency = .product(name: "Swifter", package: "swifter")
let combineExtDependency: Target.Dependency = .byName(name: "CombineExt")

let package = Package(
    name: "tuist",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "tuistbenchmark", targets: ["tuistbenchmark"]),
        .executable(name: "tuistfixturegenerator", targets: ["tuistfixturegenerator"]),
        .executable(name: "tuist", targets: ["tuist"]),
        .executable(name: "tuistenv", targets: ["tuistenv"]),
        .library(
            name: "ProjectDescription",
            type: .dynamic,
            targets: ["ProjectDescription"]
        ),
        .library(
            name: "ProjectAutomation",
            targets: ["ProjectAutomation"]
        ),
        .library(
            name: "TuistGraph",
            targets: ["TuistGraph"]
        ),
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
        .library(
            name: "TuistGenerator",
            targets: ["TuistGenerator"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.2"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.2"),
        .package(url: "https://github.com/apple/swift-tools-support-core.git", from: "0.5.1"),
        .package(url: "https://github.com/CombineCommunity/CombineExt.git", from: "1.8.1"),
        .package(url: "https://github.com/FabrizioBrancati/Queuer.git", from: "2.1.1"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", revision: "22bfd0ad22e1b2057088180e8e9c66e204755098"),
        .package(url: "https://github.com/httpswift/swifter.git", revision: "1e4f51c92d7ca486242d8bf0722b99de2c3531aa"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.6.0"),
        .package(url: "https://github.com/rnine/Checksum.git", from: "1.0.2"),
        .package(url: "https://github.com/stencilproject/Stencil.git", exact: "0.15.1"),
        .package(url: "https://github.com/SwiftDocOrg/GraphViz.git", exact: "0.2.0"),
        .package(url: "https://github.com/SwiftGen/StencilSwiftKit.git", exact: "2.10.1"),
        .package(url: "https://github.com/SwiftGen/SwiftGen", exact: "6.5.1"),
        .package(url: "https://github.com/tuist/XcodeProj.git", exact: "8.14.0"),
        .package(url: "https://github.com/tuist/swift-openapi-runtime", branch: "swift-tools-version"),
        .package(url: "https://github.com/tuist/swift-openapi-urlsession", branch: "swift-tools-version"),
    ],
    targets: [
        .executableTarget(
            name: "tuistbenchmark",
            dependencies: [
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            ]
        ),
        .executableTarget(
            name: "tuistfixturegenerator",
            dependencies: [
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
            ]
        ),
        .target(
            name: "TuistGraph",
            dependencies: [
                swiftToolsSupportDependency,
                "TuistSupport",
            ]
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
            dependencies: [
                swiftToolsSupportDependency,
                "ProjectDescription",
                "TuistSupport",
                "TuistGraph",
                "XcodeProj",
                "Checksum",
            ]
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
                "ProjectAutomation",
                "TuistLoader",
                "TuistScaffold",
                "TuistSigning",
                "TuistDependencies",
                "TuistCloud",
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
                "ProjectAutomation",
                "TuistLoaderTesting",
                "TuistCacheTesting",
                "TuistGeneratorTesting",
                "TuistScaffoldTesting",
                "TuistCloudTesting",
                "TuistAutomationTesting",
                "TuistSigningTesting",
                "TuistDependenciesTesting",
                "TuistMigrationTesting",
                "TuistAsyncQueueTesting",
                "TuistGraphTesting",
                "TuistPlugin",
                "TuistPluginTesting",
            ]
        ),
        .testTarget(
            name: "TuistKitIntegrationTests",
            dependencies: [
                "TuistKit",
                "TuistCoreTesting",
                "TuistSupportTesting",
                "ProjectDescription",
                "ProjectAutomation",
                "TuistLoaderTesting",
                "TuistCloudTesting",
                "TuistGraphTesting",
            ]
        ),
        .executableTarget(
            name: "tuist",
            dependencies: [
                "TuistKit",
                "ProjectDescription",
                "ProjectAutomation",
            ]
        ),
        .target(
            name: "TuistEnvKit",
            dependencies: [
                argumentParserDependency,
                swiftToolsSupportDependency,
                "TuistSupport",
            ]
        ),
        .testTarget(
            name: "TuistEnvKitTests",
            dependencies: [
                "TuistEnvKit",
                "TuistSupportTesting",
            ]
        ),
        .executableTarget(
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
            name: "ProjectAutomation",
            dependencies: [
                swiftToolsSupportDependency,
            ]
        ),
        .target(
            name: "TuistSupport",
            dependencies: [
                combineExtDependency,
                swiftToolsSupportDependency,
                loggingDependency,
                "KeychainAccess",
                swifterDependency,
                "ZIPFoundation",
                "Checksum",
                "ProjectDescription",
            ]
        ),
        .target(
            name: "TuistSupportTesting",
            dependencies: [
                "TuistSupport",
                "TuistGraph",
                swiftToolsSupportDependency,
            ]
        ),
        .testTarget(
            name: "TuistSupportTests",
            dependencies: [
                "TuistCore",
                "TuistSupport",
                "TuistSupportTesting",
            ]
        ),
        .testTarget(
            name: "TuistSupportIntegrationTests",
            dependencies: [
                "TuistSupport",
                "TuistSupportTesting",
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
            ]
        ),
        .testTarget(
            name: "TuistCacheTests",
            dependencies: [
                "TuistCache",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistCacheTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistCacheTesting",
            dependencies: [
                "TuistCache",
                "TuistCloud",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistSupportTesting",
                "TuistGraphTesting",
                "TuistCoreTesting",
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
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            exclude: [
                "graphql/CreateProject.graphql",
                "graphql/ClearRemoteCacheStorage.graphql",
            ]
        ),
        .testTarget(
            name: "TuistCloudTests",
            dependencies: [
                "TuistCloud",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistGraphTesting",
            ]
        ),
        .target(
            name: "TuistCloudTesting",
            dependencies: [
                "TuistCloud",
                swiftToolsSupportDependency,
                "TuistCore",
                "TuistGraphTesting",
            ]
        ),
        .testTarget(
            name: "TuistCacheIntegrationTests",
            dependencies: [
                "TuistCache",
                "TuistSupportTesting",
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
                "TuistAutomationTesting",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistGraphTesting",
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
        .target(
            name: "TuistDependencies",
            dependencies: [
                "ProjectDescription",
                "TuistCore",
                "TuistGraph",
                "TuistSupport",
                "TuistPlugin",
            ]
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
                "TuistCoreTesting",
                "TuistDependencies",
                "TuistDependenciesTesting",
                "TuistGraphTesting",
                "TuistLoaderTesting",
                "TuistSupportTesting",
                "TuistPluginTesting",
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
            ]
        ),
        .testTarget(
            name: "TuistLoaderIntegrationTests",
            dependencies: [
                "TuistLoader",
                "TuistGraphTesting",
                "TuistSupportTesting",
                "ProjectDescription",
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
                .byName(name: "AnyCodable"),
                "TuistAsyncQueue",
                "TuistCloud",
                "TuistCore",
                "TuistGraph",
                "TuistLoader",
            ]
        ),
        .testTarget(
            name: "TuistAnalyticsTests",
            dependencies: [
                "TuistAnalytics",
                "TuistSupportTesting",
                "TuistGraphTesting",
                "TuistCoreTesting",
                "XcodeProj",
            ]
        ),
        .target(
            name: "TuistPlugin",
            dependencies: [
                "TuistGraph",
                "TuistLoader",
                "TuistSupport",
                "TuistScaffold",
                swiftToolsSupportDependency,
            ]
        ),
        .target(
            name: "TuistPluginTesting",
            dependencies: [
                "TuistGraph",
                "TuistPlugin",
                swiftToolsSupportDependency,
            ]
        ),
        .testTarget(
            name: "TuistPluginTests",
            dependencies: [
                "ProjectDescription",
                "TuistLoader",
                "TuistLoaderTesting",
                "TuistGraphTesting",
                "TuistPlugin",
                "TuistSupport",
                "TuistSupportTesting",
                "TuistScaffoldTesting",
                "TuistCoreTesting",
                swiftToolsSupportDependency,
            ]
        ),
    ]
)
