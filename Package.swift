// swift-tools-version:5.9

import PackageDescription

let swiftToolsSupportDependency: Target.Dependency = .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "swift-log")
let argumentParserDependency: Target.Dependency = .product(name: "ArgumentParser", package: "swift-argument-parser")
let swiftGenKitDependency: Target.Dependency = .product(name: "SwiftGenKit", package: "SwiftGen")
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
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistGraphTesting",
        dependencies: [
            "TuistGraph",
            "TuistSupportTesting",
            swiftToolsSupportDependency,
            "AnyCodable",
        ],
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
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistCoreTesting",
        dependencies: [
            "TuistCore",
            "TuistSupportTesting",
            "TuistGraphTesting",
            swiftToolsSupportDependency,
        ],
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
            "TuistDependencies",
            "GraphViz",
            "TuistMigration",
            "TuistAsyncQueue",
            "TuistAnalytics",
            "TuistPlugin",
            "TuistGraph",
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
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
            "ZIPFoundation",
            "ProjectDescription",
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistSupportTesting",
        dependencies: [
            "TuistSupport",
            "TuistGraph",
            swiftToolsSupportDependency,
            "Difference",
        ],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistAcceptanceTesting",
        dependencies: [
            "TuistKit",
            "TuistCore",
            "TuistSupport",
            "TuistSupportTesting",
            "XcodeProj",
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
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistGeneratorTesting",
        dependencies: [
            "TuistGenerator",
            swiftToolsSupportDependency,
        ],
        linkerSettings: [.linkedFramework("XCTest")]
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
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistAutomation",
        dependencies: [
            "XcodeProj",
            swiftToolsSupportDependency,
            .product(name: "XcbeautifyLib", package: "xcbeautify"),
            "TuistCore",
            "TuistGraph",
            "TuistSupport",
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
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
            "Mockable",
            swiftToolsSupportDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistMigration",
        dependencies: [
            "TuistCore",
            "TuistGraph",
            "TuistSupport",
            "XcodeProj",
            "Mockable",
            swiftToolsSupportDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistAsyncQueue",
        dependencies: [
            "TuistCore",
            "TuistGraph",
            "TuistSupport",
            "XcodeProj",
            "Mockable",
            swiftToolsSupportDependency,
            "Queuer",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
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
            "Mockable",
            "ProjectDescription",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
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
            "Mockable",
            swiftToolsSupportDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistPlugin",
        dependencies: [
            "TuistGraph",
            "TuistLoader",
            "TuistSupport",
            "TuistScaffold",
            "Mockable",
            swiftToolsSupportDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
]

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: [
            "SystemPackage": .staticFramework,
            "TSCBasic": .staticFramework,
            "TSCUtility": .staticFramework,
            "TSCclibc": .staticFramework,
            "TSCLibc": .staticFramework,
            "ArgumentParser": .staticFramework,
            "Mockable": .staticFramework,
            "MockableTest": .staticFramework,
        ],
        // To revert once we release Tuist 4
        targetSettings: [
            "MockableTest": ["ENABLE_TESTING_SEARCH_PATHS": "YES"],
        ]
    )

#endif

let package = Package(
    name: "tuist",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "tuistbenchmark", targets: ["tuistbenchmark"]),
        .executable(name: "tuistfixturegenerator", targets: ["tuistfixturegenerator"]),
        .executable(name: "tuist", targets: ["tuist"]),
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
            name: "TuistDependencies",
            targets: ["TuistDependencies"]
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
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-tools-support-core", from: "0.6.1"),
        .package(url: "https://github.com/CombineCommunity/CombineExt", from: "1.8.1"),
        .package(url: "https://github.com/FabrizioBrancati/Queuer", from: "2.1.1"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.17"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
        .package(url: "https://github.com/stencilproject/Stencil", exact: "0.15.1"),
        .package(url: "https://github.com/SwiftDocOrg/GraphViz", exact: "0.2.0"),
        .package(url: "https://github.com/SwiftGen/StencilSwiftKit", exact: "2.10.1"),
        .package(url: "https://github.com/SwiftGen/SwiftGen", exact: "6.6.2"),
        .package(url: "https://github.com/tuist/XcodeProj", exact: "8.19.0"),
        .package(url: "https://github.com/cpisciotta/xcbeautify", from: "1.5.0"),
        .package(url: "https://github.com/krzysztofzablocki/Difference.git", from: "1.0.2"),
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.0.2"),
    ],
    targets: targets
)
