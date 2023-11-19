// swift-tools-version:5.7

import PackageDescription

let swiftToolsSupportDependency: Target.Dependency = .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "swift-log")
let argumentParserDependency: Target.Dependency = .product(name: "ArgumentParser", package: "swift-argument-parser")
let swiftGenKitDependency: Target.Dependency = .product(name: "SwiftGenKit", package: "SwiftGen")
let swifterDependency: Target.Dependency = .product(name: "Swifter", package: "swifter")
let combineExtDependency: Target.Dependency = .byName(name: "CombineExt")

var targets: [Target] = [
    .executableTarget(
        name: "tuistbenchmark",
        dependencies: [
            argumentParserDependency,
            swiftToolsSupportDependency,
        ]
    ),
    .executableTarget(
        name: "tuistfixturegenerator",
        dependencies: [
            argumentParserDependency,
            swiftToolsSupportDependency,
        ]
    ),
    .target(
        name: "TuistGraph",
        dependencies: [
            swiftToolsSupportDependency,
            "AnyCodable",
            "TuistSupport",
        ]
    ),
    .target(
        name: "TuistGraphTesting",
        dependencies: ["TuistGraph", "TuistSupportTesting"],
        linkerSettings: [.linkedFramework("XCTest")]
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
        dependencies: ["TuistCore", "TuistSupportTesting", "TuistGraphTesting"],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistKit",
        dependencies: [
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
    .target(
        name: "ProjectAutomation"
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
        ],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistAcceptanceTesting",
        dependencies: [
            "TuistKit",
            "TuistSupportTesting",
            swiftToolsSupportDependency,
        ],
        linkerSettings: [.linkedFramework("XCTest")]
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
        name: "TuistAutomation",
        dependencies: [
            "XcodeProj",
            swiftToolsSupportDependency,
            "TuistCore",
            "TuistGraph",
            "TuistSupport",
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
        ],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistAnalytics",
        dependencies: [
            .byName(name: "AnyCodable"),
            "TuistAsyncQueue",
            "TuistCore",
            "TuistGraph",
            "TuistLoader",
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
]

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
            type: .dynamic,
            targets: ["ProjectAutomation"]
        ),
        .library(
            name: "TuistGraph",
            targets: ["TuistGraph"]
        ),
        .library(
            name: "TuistGraphTesting",
            targets: ["TuistGraphTesting"]
        ),
        .library(
            name: "TuistKit",
            targets: ["TuistKit"]
        ),
        .library(
            name: "TuistSupport",
            targets: ["TuistSupport"]
        ),
        .library(
            name: "TuistSupportTesting",
            targets: ["TuistSupportTesting"]
        ),
        .library(
            name: "TuistCore",
            targets: ["TuistCore"]
        ),
        .library(
            name: "TuistCoreTesting",
            targets: ["TuistCoreTesting"]
        ),
        .library(
            name: "TuistLoader",
            targets: ["TuistLoader"]
        ),
        .library(
            name: "TuistLoaderTesting",
            targets: ["TuistLoaderTesting"]
        ),
        .library(
            name: "TuistAnalytics",
            targets: ["TuistAnalytics"]
        ),
        .library(
            name: "TuistAutomation",
            targets: ["TuistAutomation"]
        ),
        .library(
            name: "TuistSigning",
            targets: ["TuistSigning"]
        ),
        .library(
            name: "TuistAcceptanceTesting",
            targets: ["TuistAcceptanceTesting"]
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
    ],
    targets: targets
)
