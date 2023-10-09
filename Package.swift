// swift-tools-version:5.7

import PackageDescription

var includeTuistCloud = false

#if canImport(Foundation)
import Foundation
includeTuistCloud = ProcessInfo.processInfo.environment["TUIST_INCLUDE_TUIST_CLOUD"] == "1"
#endif
if includeTuistCloud {
    print("Including TuistCloud sources")
}
includeTuistCloud = true

let swiftToolsSupportDependency: Target.Dependency = .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "swift-log")
let argumentParserDependency: Target.Dependency = .product(name: "ArgumentParser", package: "swift-argument-parser")
let swiftGenKitDependency: Target.Dependency = .product(name: "SwiftGenKit", package: "SwiftGen")
let swifterDependency: Target.Dependency = .product(name: "Swifter", package: "swifter")
let combineExtDependency: Target.Dependency = .byName(name: "CombineExt")

func mapDependenciesOfSourcesTargetDependentOnTuistCloud(_ dependencies: [Target.Dependency]) -> [Target.Dependency] {
    var dependencies = dependencies
    if includeTuistCloud {
        dependencies.append("TuistCloud")
    }
    return dependencies
}

func mapDependenciesOfTestsTargetDependentOnTuistCloud(_ dependencies: [Target.Dependency]) -> [Target.Dependency] {
    var dependencies = dependencies
    if includeTuistCloud {
        dependencies.append("TuistCloud")
        dependencies.append("TuistCloudTesting")
    }
    return dependencies
}

var targets: [Target] = [
    .executableTarget(
        name: "tuistbenchmark",
        dependencies: [
            argumentParserDependency,
            .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
        ]
    ),
    .executableTarget(
        name: "tuistfixturegenerator",
        dependencies: [
            argumentParserDependency,
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
        dependencies: mapDependenciesOfSourcesTargetDependentOnTuistCloud([
            "XcodeProj",
            swiftToolsSupportDependency,
            argumentParserDependency,
            "TuistSupport",
            "TuistGenerator",
            "TuistAutomation",
            "ProjectDescription",
            "ProjectAutomation",
            "TuistLoader",
            "TuistScaffold",
            "TuistSigning",
            "TuistDependencies",
            "GraphViz",
            "TuistMigration",
            "TuistAsyncQueue",
            "TuistAnalytics",
            "TuistPlugin",
            "TuistGraph",
        ])
    ),
    .testTarget(
        name: "TuistKitTests",
        dependencies: mapDependenciesOfTestsTargetDependentOnTuistCloud([
            "TuistKit",
            "TuistAutomation",
            "TuistSupportTesting",
            "TuistCoreTesting",
            "ProjectDescription",
            "ProjectAutomation",
            "TuistLoaderTesting",
            "TuistGeneratorTesting",
            "TuistScaffoldTesting",
            "TuistAutomationTesting",
            "TuistSigningTesting",
            "TuistDependenciesTesting",
            "TuistMigrationTesting",
            "TuistAsyncQueueTesting",
            "TuistGraphTesting",
            "TuistPlugin",
            "TuistPluginTesting",
        ])
    ),
    .testTarget(
        name: "TuistKitIntegrationTests",
        dependencies: mapDependenciesOfTestsTargetDependentOnTuistCloud([
            "TuistKit",
            "TuistCoreTesting",
            "TuistSupportTesting",
            "ProjectDescription",
            "ProjectAutomation",
            "TuistLoaderTesting",
            "TuistGraphTesting",
        ])
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
            // TODO: TuistCloud
            // "TuistCloud",
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

if includeTuistCloud {
    targets.append(contentsOf: [
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
            exclude: ["OpenAPI/cloud.yml"]
        ),
        .testTarget(
            name: "TuistCloudTests",
            dependencies: [
                "TuistCloud",
                "TuistCloudTesting",
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
            name: "TuistCloudIntegrationTests",
            dependencies: [
                "TuistCloud",
                "TuistSupportTesting",
                "TuistCoreTesting",
                "TuistGraphTesting",
            ]
        ),
    ])
}

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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.3"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-tools-support-core", from: "0.6.1"),
        .package(url: "https://github.com/CombineCommunity/CombineExt", from: "1.8.1"),
        .package(url: "https://github.com/FabrizioBrancati/Queuer", from: "2.1.1"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.17"),
        .package(url: "https://github.com/httpswift/swifter.git", revision: "1e4f51c92d7ca486242d8bf0722b99de2c3531aa"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
        .package(url: "https://github.com/rnine/Checksum", from: "1.0.2"),
        .package(url: "https://github.com/stencilproject/Stencil", exact: "0.15.1"),
        .package(url: "https://github.com/SwiftDocOrg/GraphViz", exact: "0.2.0"),
        .package(url: "https://github.com/SwiftGen/StencilSwiftKit", exact: "2.10.1"),
        .package(url: "https://github.com/SwiftGen/SwiftGen", exact: "6.6.2"),
        .package(url: "https://github.com/tuist/XcodeProj", exact: "8.15.0"),
        .package(url: "https://github.com/tuist/swift-openapi-runtime", branch: "swift-tools-version"),
        .package(url: "https://github.com/tuist/swift-openapi-urlsession", branch: "swift-tools-version"),
    ],
    targets: targets
)
