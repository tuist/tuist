// swift-tools-version: 6.1

@preconcurrency import PackageDescription

let swiftToolsSupportDependency: Target.Dependency = .product(
    name: "SwiftToolsSupport-auto", package: "swiftlang.swift-tools-support-core"
)
let pathDependency: Target.Dependency = .product(name: "Path", package: "tuist.Path")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "apple.swift-log")
let argumentParserDependency: Target.Dependency = .product(
    name: "ArgumentParser", package: "apple.swift-argument-parser"
)
let swiftGenKitDependency: Target.Dependency = .product(
    name: "SwiftGenKit", package: "swiftGen.SwiftGen")

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
            .product(name: "XcodeMetadata", package: "tuist.XcodeGraph"),
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
            "TuistCI",
            "TuistCAS",
            "TuistLaunchctl",
            .product(name: "Noora", package: "tuist.Noora"),
            .product(name: "Command", package: "tuist.Command"),
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "XcodeGraphMapper", package: "tuist.XcodeGraph"),
            .byName(name: "AnyCodable"),
            .product(name: "XCResultKit", package: "davidahouse.XCResultKit"),
            .product(name: "MCP", package: "modelcontextprotocol.swift-sdk"),
            .product(name: "SwiftyJSON", package: "swiftyJSON.SwiftyJSON"),
            .product(name: "Rosalind", package: "tuist.Rosalind"),
            .product(name: "GRPCNIOTransportHTTP2", package: "grpc.grpc-swift-nio-transport"),
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
            .product(name: "Noora", package: "tuist.Noora"),
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
            .product(name: "Noora", package: "tuist.Noora"),
            .product(name: "LoggingOSLog", package: "chrisaljoudi.swift-log-oslog"),
            .product(name: "FileLogging", package: "crspybits.swift-log-file"),
            .product(name: "XCLogParser", package: "MobileNativeFoundation.XCLogParser"),
            .product(name: "OrderedSet", package: "frazer-rbsn.OrderedSet"),
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
            .product(name: "FileSystemTesting", package: "tuist.FileSystem"),
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
            .product(name: "XcbeautifyLib", package: "cpisciotta.xcbeautify"),
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
            .target(name: "TuistCI", condition: .when(platforms: [.macOS])),
            .target(name: "TuistProcess", condition: .when(platforms: [.macOS])),
            pathDependency,
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "apple.swift-http-types"),
            .product(name: "OpenAPIURLSession", package: "apple.swift-openapi-urlsession"),
            .product(name: "Rosalind", package: "tuist.Rosalind"),
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
            "TuistCASAnalytics",
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
    .target(
        name: "TuistCI",
        dependencies: [
            "TuistSupport",
            "Mockable",
            pathDependency,
        ],
        path: "cli/Sources/TuistCI",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistCAS",
        dependencies: [
            "TuistServer",
            "TuistRootDirectoryLocator",
            "TuistCASAnalytics",
            .product(name: "GRPCCore", package: "grpc.grpc-swift-2"),
            .product(name: "GRPCProtobuf", package: "grpc.grpc-swift-protobuf"),
            .product(name: "SwiftProtobuf", package: "apple.swift-protobuf"),
            .product(name: "libzstd", package: "facebook.zstd"),
            "Mockable",
            pathDependency,
        ],
        path: "cli/Sources/TuistCAS",
        exclude: ["cas.proto", "keyvalue.proto", "grpc-swift-proto-generator-config.json"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistCASAnalytics",
        dependencies: [
            "TuistSupport",
            "FileSystem",
            pathDependency,
            "Mockable",
        ],
        path: "cli/Sources/TuistCASAnalytics",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistLaunchctl",
        dependencies: [
            "Command",
            "Mockable",
            pathDependency,
        ],
        path: "cli/Sources/TuistLaunchctl",
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
    platforms: [.macOS(.v15)],
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
        .package(id: "apple.swift-argument-parser", from: "1.5.0"),
        .package(id: "apple.swift-log", from: "1.5.3"),
        .package(id: "swiftlang.swift-tools-support-core", from: "0.6.1"),
        .package(id: "fabrizioBrancati.Queuer", from: "2.1.1"),
        .package(id: "flight-school.AnyCodable", from: "0.6.7"),
        .package(id: "tuist.ZIPFoundation", from: "0.9.19"),
        .package(id: "kishikawakatsumi.KeychainAccess", from: "4.2.2"),
        .package(id: "stencilproject.Stencil", exact: "0.15.1"),
        .package(id: "tuist.GraphViz", exact: "0.4.2"),
        .package(id: "swiftGen.StencilSwiftKit", exact: "2.10.1"),
        .package(id: "swiftGen.SwiftGen", exact: "6.6.2"),
        .package(id: "tuist.XcodeProj", .upToNextMajor(from: "9.4.3")),
        .package(id: "cpisciotta.xcbeautify", from: "3.1.0"),
        .package(id: "krzysztofzablocki.Difference", from: "1.0.2"),
        .package(id: "kolos65.Mockable", .upToNextMajor(from: "0.3.1")),
        .package(
            id: "apple.swift-openapi-runtime", .upToNextMajor(from: "1.5.0")
        ),
        .package(
            id: "apple.swift-http-types", .upToNextMajor(from: "1.3.0")
        ),
        .package(
            id: "apple.swift-openapi-urlsession", .upToNextMajor(from: "1.0.2")
        ),
        .package(id: "tuist.Path", .upToNextMajor(from: "0.3.0")),
        .package(id: "tuist.XcodeGraph", .upToNextMajor(from: "1.29.0")),
        .package(id: "tuist.FileSystem", .upToNextMajor(from: "0.11.0")),
        .package(id: "tuist.Command", .upToNextMajor(from: "0.8.0")),
        .package(id: "sparkle-project.Sparkle", from: "2.6.4"),
        .package(id: "apple.swift-collections", .upToNextMajor(from: "1.1.4")),
        .package(
            id: "apple.swift-service-context", .upToNextMajor(from: "1.0.0")
        ),
        .package(
            id: "chrisaljoudi.swift-log-oslog",
            .upToNextMajor(from: "0.2.2")
        ),
        .package(id: "crspybits.swift-log-file", .upToNextMajor(from: "0.1.0")),
        .package(
            id: "MobileNativeFoundation.XCLogParser",
            .upToNextMajor(from: "0.2.43")
        ),
        .package(id: "davidahouse.XCResultKit", .upToNextMajor(from: "1.2.2")),
        .package(id: "tuist.Noora", .upToNextMajor(from: "0.45.0")),
        .package(
            id: "frazer-rbsn.OrderedSet", .upToNextMajor(from: "2.0.0")
        ),
        .package(
            id: "pointfreeco.swift-snapshot-testing",
            .upToNextMajor(from: "1.18.1")
        ),
        .package(
            id: "modelcontextprotocol.swift-sdk",
            .upToNextMajor(from: "0.9.0")
        ),
        .package(id: "swiftyJSON.SwiftyJSON", .upToNextMajor(from: "5.0.2")),
        .package(
            id: "tuist.Rosalind",
            .upToNextMajor(from: "0.6.0")
        ),
        .package(id: "kean.Nuke", .upToNextMajor(from: "12.8.0")),
        .package(id: "leif-ibsen.SwiftECC", exact: "5.5.0"),
        .package(
            id: "wadetregaskis.FluidMenuBarExtra", .upToNextMajor(from: "1.1.0")),
        .package(id: "grpc.grpc-swift-2", from: "2.0.0"),
        .package(
            id: "apple.swift-protobuf",
            from: "1.32.0"
        ),
        .package(id: "grpc.grpc-swift-protobuf", from: "2.0.0"),
        .package(id: "grpc.grpc-swift-nio-transport", from: "2.0.0"),
        .package(id: "facebook.zstd", from: "1.5.0"),
    ],
    targets: targets,
    swiftLanguageModes: [.v5]
)
