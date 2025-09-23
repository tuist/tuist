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
            "TuistSupport",
        ],
        path: "cli/Sources/tuistbenchmark"
    ),
    .executableTarget(
        name: "tuistfixturegenerator",
        dependencies: [
            argumentParserDependency,
            pathDependency,
            swiftToolsSupportDependency,
            pathDependency,
            "ProjectDescription",
            "TuistSupport",
        ],
        path: "cli/Sources/tuistfixturegenerator"
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
            "TuistSimulator",
            .product(name: "XcodeMetadata", package: "XcodeGraph"),
            .byName(name: "AnyCodable"),
        ],
        path: "cli/Sources/TuistCore",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistKit",
        dependencies: [
            "XcodeProj",
            pathDependency,
            argumentParserDependency,
            .target(name: "TuistProcess", condition: .when(platforms: [.macOS])),
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
            "TuistRootDirectoryLocator",
            .product(name: "Noora", package: "Noora"),
            .product(name: "Command", package: "Command"),
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "XcodeGraphMapper", package: "XcodeGraph"),
            .byName(name: "AnyCodable"),
            .product(name: "XCResultKit", package: "XCResultKit"),
            .product(name: "MCP", package: "swift-sdk"),
            .product(name: "SwiftyJSON", package: "SwiftyJSON"),
            .product(name: "Rosalind", package: "Rosalind"),
        ],
        path: "cli/Sources/TuistKit",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        ],
        path: "cli/Sources/tuist",
    ),
    .target(
        name: "ProjectDescription",
        dependencies: [],
        path: "cli/Sources/ProjectDescription",
    ),
    .target(
        name: "ProjectAutomation",
        path: "cli/Sources/ProjectAutomation",
    ),
    .target(
        name: "TuistSupport",
        dependencies: [
            pathDependency,
            loggingDependency,
            swiftToolsSupportDependency,
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
        path: "cli/Sources/TuistSupport",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistTesting",
        dependencies: [
            "TuistSupport",
            "TuistServer",
            "XcodeGraph",
            pathDependency,
            "Difference",
            "FileSystem",
            .product(name: "FileSystemTesting", package: "FileSystem"),
            argumentParserDependency,
        ],
        path: "cli/Sources/TuistTesting",
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistAcceptanceTesting",
        dependencies: [
            "TuistKit",
            "TuistCore",
            "TuistSupport",
            "TuistTesting",
            "XcodeProj",
            "FileSystem",
            "ProjectDescription",
            "XcodeGraph",
            pathDependency,
        ],
        path: "cli/Sources/TuistAcceptanceTesting",
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
            "TuistRootDirectoryLocator",
        ],
        path: "cli/Sources/TuistGenerator",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
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
            "TuistRootDirectoryLocator",
        ],
        path: "cli/Sources/TuistScaffold",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        path: "cli/Sources/TuistAutomation",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        path: "cli/Sources/TuistDependencies",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        path: "cli/Sources/TuistMigration",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        path: "cli/Sources/TuistAsyncQueue",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            "TuistRootDirectoryLocator",
            "TuistGit",
        ],
        path: "cli/Sources/TuistLoader",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistProcess",
        dependencies: [
            "Mockable"
        ],
        path: "cli/Sources/TuistProcess",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistAnalytics",
        dependencies: [
            .byName(name: "AnyCodable"),
            "TuistAsyncQueue",
            "TuistServer",
            "TuistCore",
            "XcodeGraph",
            "TuistLoader",
            "TuistSupport",
            "Mockable",
            pathDependency,
        ],
        path: "cli/Sources/TuistAnalytics",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        path: "cli/Sources/TuistPlugin",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistServer",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "TuistCache",
            "TuistXCActivityLog",
            "FileSystem",
            "XcodeGraph",
            "Mockable",
            "KeychainAccess",
            .target(name: "TuistProcess", condition: .when(platforms: [.macOS])),
            pathDependency,
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .product(name: "Rosalind", package: "Rosalind"),
        ],
        path: "cli/Sources/TuistServer",
        exclude: ["OpenAPI/server.yml"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistHasher",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "FileSystem",
            "TuistRootDirectoryLocator",
            pathDependency,
            "XcodeGraph",
            "Mockable",
        ],
        path: "cli/Sources/TuistHasher",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        path: "cli/Sources/TuistCache",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistSimulator",
        dependencies: [
            "XcodeGraph",
            "Mockable",
            pathDependency,
        ],
        path: "cli/Sources/TuistSimulator",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistXCActivityLog",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "TuistRootDirectoryLocator",
            "TuistGit",
            "FileSystem",
            "XCLogParser",
            swiftToolsSupportDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistXCActivityLog",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistGit",
        dependencies: [
            "TuistSupport",
            "FileSystem",
            swiftToolsSupportDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistGit",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistRootDirectoryLocator",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "FileSystem",
            pathDependency,
        ],
        path: "cli/Sources/TuistRootDirectoryLocator",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            name: "TuistTesting",
            targets: ["TuistTesting"]
        ),
        .library(
            name: "TuistCore",
            targets: ["TuistCore"]
        ),
        .library(
            name: "TuistXCActivityLog",
            targets: ["TuistXCActivityLog"]
        ),
        .library(
            name: "TuistLoader",
            targets: ["TuistLoader"]
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
        // TuistGenerator
        //
        // A high level Xcode generator library
        // responsible for generating Xcode projects & workspaces.
        //
        // This library can be used in external tools that wish to
        // leverage Tuist's Xcode generation features.
        //
        // Note: This library should be treated as **unstable** as
        //       it is still under development and may include breaking
        //       changes in future releases.
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
        .package(url: "https://github.com/tuist/XcodeProj", .upToNextMajor(from: "9.4.3")),
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
        .package(url: "https://github.com/tuist/XcodeGraph", .upToNextMajor(from: "1.20.0")),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.11.0")),
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
        .package(
            url: "https://github.com/MobileNativeFoundation/XCLogParser",
            branch: "master"
        ),
        .package(url: "https://github.com/davidahouse/XCResultKit", .upToNextMajor(from: "1.2.2")),
        .package(url: "https://github.com/tuist/Noora", .upToNextMajor(from: "0.45.0")),
        .package(
            url: "https://github.com/frazer-rbsn/OrderedSet.git", .upToNextMajor(from: "2.0.0")
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            .upToNextMajor(from: "1.18.1")
        ),
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            .upToNextMajor(from: "0.9.0")
        ),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", .upToNextMajor(from: "5.0.2")),
        .package(
            url: "https://github.com/tuist/Rosalind",
            .upToNextMajor(from: "0.5.108")
        ),
        .package(url: "https://github.com/kean/Nuke", .upToNextMajor(from: "12.8.0")),
        .package(url: "https://github.com/leif-ibsen/SwiftECC", exact: "5.5.0"),
        .package(
            url: "https://github.com/lfroms/fluid-menu-bar-extra", .upToNextMajor(from: "1.1.0")),
    ],
    targets: targets
)
