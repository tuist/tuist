// swift-tools-version: 5.10

@preconcurrency import PackageDescription

let swiftToolsSupportDependency: Target.Dependency = .product(
    name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"
)
let pathDependency: Target.Dependency = .product(name: "Path", package: "Path")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "swift-log")
let argumentParserDependency: Target.Dependency = .product(
    name: "ArgumentParser", package: "swift-argument-parser"
)
let swiftGenKitDependency: Target.Dependency = .product(name: "SwiftGenKit", package: "SwiftGen")

let targets: [Target] = [
    .executableTarget(
        name: "tuistbenchmark",
        dependencies: [
            argumentParserDependency,
            pathDependency,
            swiftToolsSupportDependency,
            "FileSystem",
        ]
    ),
    .executableTarget(
        name: "tuistfixturegenerator",
        dependencies: [
            argumentParserDependency,
            pathDependency,
            swiftToolsSupportDependency,
            "ProjectDescription",
        ]
    ),
    .target(
        name: "TuistCore",
        dependencies: [
            pathDependency,
            "TuistSupport",
            "XcodeGraph",
            "XcodeProj",
            "Mockable",
            "FileSystem",
            .byName(name: "AnyCodable"),
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
            "TuistSupport",
            "XcodeGraph",
            pathDependency,
        ],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistKit",
        dependencies: [
            "XcodeProj",
            pathDependency,
            argumentParserDependency,
            "TuistCore",
            "TuistSupport",
            "TuistGenerator",
            "TuistAutomation",
            "ProjectDescription",
            "ProjectAutomation",
            "TuistLoader",
            "TuistHasher",
            "TuistScaffold",
            "TuistDependencies",
            "GraphViz",
            "TuistMigration",
            "TuistAsyncQueue",
            "TuistAnalytics",
            "TuistPlugin",
            "XcodeGraph",
            "Mockable",
            "TuistServer",
            "FileSystem",
            "TuistCache",
            .product(name: "Command", package: "Command"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .byName(name: "AnyCodable"),
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .executableTarget(
        name: "tuist",
        dependencies: [
            "TuistKit",
            "TuistSupport",
            "TuistLoader",
            "ProjectDescription",
            "ProjectAutomation",
            pathDependency,
            swiftToolsSupportDependency,
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
            pathDependency,
            loggingDependency,
            swiftToolsSupportDependency,
            "KeychainAccess",
            "ZIPFoundation",
            "Mockable",
            "FileSystem",
            "Command",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistSupportTesting",
        dependencies: [
            "TuistSupport",
            "XcodeGraph",
            pathDependency,
            "Difference",
            "FileSystem",
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
            "FileSystem",
            "ProjectDescription",
            "XcodeGraph",
            pathDependency,
        ],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistGenerator",
        dependencies: [
            "XcodeProj",
            pathDependency,
            "TuistCore",
            "XcodeGraph",
            "TuistSupport",
            "GraphViz",
            swiftGenKitDependency,
            "StencilSwiftKit",
            "Mockable",
            "FileSystem",
            "Stencil",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistGeneratorTesting",
        dependencies: [
            "TuistGenerator",
            pathDependency,
            "XcodeGraph",
            "XcodeProj",
            "TuistCore",
            "TuistSupport",
        ],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistScaffold",
        dependencies: [
            pathDependency,
            "TuistCore",
            "XcodeGraph",
            "TuistSupport",
            "StencilSwiftKit",
            "Stencil",
            "Mockable",
            "FileSystem",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistAutomation",
        dependencies: [
            "XcodeProj",
            pathDependency,
            .product(name: "XcbeautifyLib", package: "xcbeautify"),
            "TuistCore",
            "XcodeGraph",
            "TuistSupport",
            "Mockable",
            "FileSystem",
            "Command",
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
            "XcodeGraph",
            "TuistSupport",
            "TuistPlugin",
            "Mockable",
            pathDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistMigration",
        dependencies: [
            "TuistCore",
            "XcodeGraph",
            "TuistSupport",
            "XcodeProj",
            "Mockable",
            "FileSystem",
            pathDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistAsyncQueue",
        dependencies: [
            "TuistCore",
            "XcodeGraph",
            "TuistSupport",
            "XcodeProj",
            "Mockable",
            pathDependency,
            "Queuer",
            "FileSystem",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistLoader",
        dependencies: [
            "XcodeProj",
            pathDependency,
            "TuistCore",
            "XcodeGraph",
            "TuistSupport",
            "Mockable",
            "ProjectDescription",
            "FileSystem",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistLoaderTesting",
        dependencies: [
            "TuistLoader",
            pathDependency,
            "TuistCore",
            "ProjectDescription",
            "TuistSupportTesting",
            "TuistSupport",
            "XcodeGraph",
        ],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistAnalytics",
        dependencies: [
            .byName(name: "AnyCodable"),
            "TuistAsyncQueue",
            "TuistCore",
            "XcodeGraph",
            "TuistLoader",
            "TuistSupport",
            "Mockable",
            pathDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistPlugin",
        dependencies: [
            "XcodeGraph",
            "TuistLoader",
            "TuistCore",
            "TuistSupport",
            "TuistScaffold",
            "Mockable",
            "FileSystem",
            pathDependency,
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistServer",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "TuistCache",
            "FileSystem",
            "XcodeGraph",
            "Mockable",
            pathDependency,
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
        ],
        exclude: ["OpenAPI/server.yml"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistHasher",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "FileSystem",
            pathDependency,
            "XcodeGraph",
            "Mockable",
        ],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistCache",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "FileSystem",
            "Mockable",
            pathDependency,
            "XcodeGraph",
            "TuistHasher",
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
            "FileSystem": .staticFramework,
            "TSCBasic": .staticFramework,
            "TSCUtility": .staticFramework,
            "TSCclibc": .staticFramework,
            "TSCLibc": .staticFramework,
            "ArgumentParser": .staticFramework,
            "Mockable": .staticFramework,
        ],
        baseSettings: .settings(base: ["GENERATE_MASTER_OBJECT_FILE": "YES"])
    )

#endif

let package = Package(
    name: "tuist",
    platforms: [.macOS(.v13)],
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
            name: "ProjectAutomation-auto",
            targets: ["ProjectAutomation"]
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
        .library(
            name: "TuistServer",
            targets: ["TuistServer"]
        ),
        .library(
            name: "TuistHasher",
            targets: ["TuistHasher"]
        ),
        .library(
            name: "TuistCache",
            targets: ["TuistCache"]
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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.5.3"),
        .package(url: "https://github.com/apple/swift-tools-support-core", from: "0.6.1"),
        .package(url: "https://github.com/FabrizioBrancati/Queuer", from: "2.1.1"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
        .package(url: "https://github.com/stencilproject/Stencil", exact: "0.15.1"),
        .package(url: "https://github.com/tuist/GraphViz.git", exact: "0.4.2"),
        .package(url: "https://github.com/SwiftGen/StencilSwiftKit", exact: "2.10.1"),
        .package(url: "https://github.com/SwiftGen/SwiftGen", exact: "6.6.2"),
        .package(url: "https://github.com/tuist/XcodeProj", exact: "8.24.4"),
        .package(url: "https://github.com/cpisciotta/xcbeautify", .upToNextMajor(from: "2.13.0")),
        .package(url: "https://github.com/krzysztofzablocki/Difference.git", from: "1.0.2"),
        .package(url: "https://github.com/Kolos65/Mockable.git", exact: "0.0.11"),
        .package(
            url: "https://github.com/apple/swift-openapi-runtime", .upToNextMajor(from: "1.5.0")
        ),
        .package(
            url: "https://github.com/apple/swift-http-types", .upToNextMajor(from: "1.3.0")
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-urlsession", .upToNextMajor(from: "1.0.2")
        ),
        .package(url: "https://github.com/tuist/Path", .upToNextMajor(from: "0.3.0")),
        .package(
            url: "https://github.com/tuist/XcodeGraph.git", exact: "1.1.0"
        ),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.6.17")),
        .package(url: "https://github.com/tuist/Command.git", exact: "0.8.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
        .package(url: "https://github.com/apple/swift-collections", .upToNextMajor(from: "1.1.4")),
    ],
    targets: targets
)
