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
            "TuistSimulator",
            "FileSystem",
            "TuistCache",
            .product(name: "Noora", package: "Noora"),
            .product(name: "Command", package: "Command"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "XcodeGraphMapper", package: "XcodeGraph"),
            .byName(name: "AnyCodable"),
            .product(name: "XCResultKit", package: "XCResultKit"),
            .product(name: "MCP", package: "mcp-swift-sdk"),
            .product(name: "SwiftyJSON", package: "SwiftyJSON"),
            .product(name: "Rosalind", package: "Rosalind"),
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
            .product(name: "Noora", package: "Noora"),
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
            .product(name: "Noora", package: "Noora"),
            .product(name: "LoggingOSLog", package: "swift-log-oslog"),
            .product(name: "FileLogging", package: "swift-log-file"),
            .product(name: "XCLogParser", package: "XCLogParser"),
            .product(name: "OrderedSet", package: "OrderedSet"),
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
            .product(name: "FileSystemTesting", package: "FileSystem"),
            argumentParserDependency,
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
            .product(name: "Rosalind", package: "Rosalind"),
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
    .target(
        name: "TuistSimulator",
        dependencies: [
            "XcodeGraph",
            "Mockable",
            pathDependency,
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
            "Noora": .staticFramework,
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
    platforms: [.macOS(.v14)],
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
        .package(url: "https://github.com/tuist/ZIPFoundation", from: "0.9.19"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
        .package(url: "https://github.com/stencilproject/Stencil", exact: "0.15.1"),
        .package(url: "https://github.com/tuist/GraphViz.git", exact: "0.4.2"),
        .package(url: "https://github.com/SwiftGen/StencilSwiftKit", exact: "2.10.1"),
        .package(url: "https://github.com/SwiftGen/SwiftGen", exact: "6.6.2"),
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "9.4.0")),
        .package(url: "https://github.com/cpisciotta/xcbeautify", .upToNextMajor(from: "2.20.0")),
        .package(url: "https://github.com/krzysztofzablocki/Difference.git", from: "1.0.2"),
        .package(url: "https://github.com/Kolos65/Mockable.git", .upToNextMajor(from: "0.3.1")),
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
        .package(url: "https://github.com/tuist/XcodeGraph", .upToNextMajor(from: "1.14.0")),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.8.0")),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMajor(from: "0.8.0")),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
        .package(url: "https://github.com/apple/swift-collections", .upToNextMajor(from: "1.1.4")),
        .package(
            url: "https://github.com/apple/swift-service-context", .upToNextMajor(from: "1.0.0")
        ),
        .package(
            url: "https://github.com/chrisaljoudi/swift-log-oslog.git",
            .upToNextMajor(from: "0.2.2")
        ),
        .package(url: "https://github.com/crspybits/swift-log-file", .upToNextMajor(from: "0.1.0")),
        .package(url: "https://github.com/tuist/XCLogParser", .upToNextMajor(from: "0.2.41")),
        .package(url: "https://github.com/davidahouse/XCResultKit", .upToNextMajor(from: "1.2.2")),
        .package(url: "https://github.com/tuist/Noora", .upToNextMajor(from: "0.38.0")),
        .package(
            url: "https://github.com/frazer-rbsn/OrderedSet.git", .upToNextMajor(from: "2.0.0")
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            .upToNextMajor(from: "1.18.1")
        ),
        .package(
            url: "https://github.com/loopwork-ai/mcp-swift-sdk.git", .upToNextMajor(from: "0.5.1")
        ),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", .upToNextMajor(from: "5.0.2")),
        .package(
            url: "https://github.com/tuist/Rosalind",
            .upToNextMajor(from: "0.5.13")
        ),
    ],
    targets: targets
)
