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
let fileSystemDependency: Target.Dependency = .product(name: "FileSystem", package: "tuist.FileSystem")
let commandDependency: Target.Dependency = .product(name: "Command", package: "tuist.Command")
let xcodeGraphDependency: Target.Dependency = .product(name: "XcodeGraph", package: "tuist.XcodeGraph")
let xcodeProjDependency: Target.Dependency = .product(name: "XcodeProj", package: "tuist.XcodeProj")
let mockableDependency: Target.Dependency = .product(name: "Mockable", package: "kolos65.Mockable")
let zipFoundationDependency: Target.Dependency = .product(name: "ZIPFoundation", package: "tuist.ZIPFoundation")
let stencilDependency: Target.Dependency = .product(name: "Stencil", package: "stencilproject.Stencil")
let graphVizDependency: Target.Dependency = .product(name: "GraphViz", package: "tuist.GraphViz")
let differenceDependency: Target.Dependency = .product(name: "Difference", package: "krzysztofzablocki.Difference")
let anyCodableDependency: Target.Dependency = .product(name: "AnyCodable", package: "flight-school.AnyCodable")

// MARK: - Targets

var targets: [Target] = [
    // MARK: Cross-platform targets
    .executableTarget(
        name: "tuist",
        dependencies: [
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            "TuistNooraExtension",
            "TuistAlert",
            .product(name: "Noora", package: "tuist.Noora"),
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            "TuistAuthCommand",
            "TuistCacheCommand",
            "TuistVersionCommand",
            argumentParserDependency,
            "TuistServer",
            pathDependency,
            swiftToolsSupportDependency,
            .target(name: "TuistKit", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCore", condition: .when(platforms: [.macOS])),
            .target(name: "TuistLoader", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            .target(name: "TuistExtension", condition: .when(platforms: [.macOS])),
            .target(name: "TuistHAR", condition: .when(platforms: [.macOS])),
        ],
        path: "cli/Sources/tuist",
        exclude: ["AGENTS.md"]
    ),
    .target(
        name: "TuistConstants",
        path: "cli/Sources/TuistConstants"
    ),
    .target(
        name: "TuistEnvironment",
        dependencies: [
            pathDependency,
            fileSystemDependency,
            mockableDependency,
            .product(name: "NIOCore", package: "apple.swift-nio"),
        ],
        path: "cli/Sources/TuistEnvironment",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistEnvironmentTesting",
        dependencies: [
            pathDependency,
            "TuistEnvironment",
        ],
        path: "cli/Sources/TuistEnvironmentTesting"
    ),
    .target(
        name: "TuistLogging",
        dependencies: [
            loggingDependency,
            pathDependency,
            fileSystemDependency,
            "TuistConstants",
            "TuistEnvironment",
            "TuistAlert",
            .product(name: "LoggingOSLog", package: "chrisaljoudi.swift-log-oslog", condition: .when(platforms: [.macOS])),
        ],
        path: "cli/Sources/TuistLogging"
    ),
    .target(
        name: "TuistUserInputReader",
        dependencies: [
            loggingDependency,
            mockableDependency,
            "TuistLogging",
        ],
        path: "cli/Sources/TuistUserInputReader",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistNooraExtension",
        dependencies: [
            .product(name: "Noora", package: "tuist.Noora"),
        ],
        path: "cli/Sources/TuistNooraExtension"
    ),
    .target(
        name: "TuistThreadSafe",
        dependencies: [],
        path: "cli/Sources/TuistThreadSafe"
    ),
    .target(
        name: "TuistEncodable",
        dependencies: [
            swiftToolsSupportDependency,
        ],
        path: "cli/Sources/TuistEncodable"
    ),
    .target(
        name: "TuistAlert",
        dependencies: [
            .product(name: "Noora", package: "tuist.Noora"),
            .product(name: "OrderedSet", package: "frazer-rbsn.OrderedSet"),
            "TuistNooraExtension",
            "TuistThreadSafe",
        ],
        path: "cli/Sources/TuistAlert"
    ),
    .target(
        name: "TuistOpener",
        dependencies: [
            pathDependency,
            fileSystemDependency,
            mockableDependency,
            "TuistLogging",
        ],
        path: "cli/Sources/TuistOpener",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistUniqueIDGenerator",
        dependencies: [
            mockableDependency,
        ],
        path: "cli/Sources/TuistUniqueIDGenerator",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistEnvKey",
        dependencies: [
            argumentParserDependency,
            "TuistEnvironment",
        ],
        path: "cli/Sources/TuistEnvKey"
    ),
    .target(
        name: "TuistCacheCommand",
        dependencies: [
            pathDependency,
            argumentParserDependency,
            loggingDependency,
            swiftToolsSupportDependency,
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            "TuistServer",
            "TuistOIDC",
            "TuistEnvKey",
            "TuistCAS",
            "TuistEncodable",
            "TuistHTTP",
            "TuistAlert",
            .target(name: "TuistLoader", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            .target(name: "TuistExtension", condition: .when(platforms: [.macOS])),
        ],
        path: "cli/Sources/TuistCacheCommand"
    ),
    .target(
        name: "TuistAuthCommand",
        dependencies: [
            pathDependency,
            argumentParserDependency,
            loggingDependency,
            swiftToolsSupportDependency,
            fileSystemDependency,
            mockableDependency,
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            "TuistEnvKey",
            "TuistServer",
            "TuistOIDC",
            "TuistUserInputReader",
            .target(name: "TuistLoader", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
        ],
        path: "cli/Sources/TuistAuthCommand",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistVersionCommand",
        dependencies: [
            argumentParserDependency,
            "TuistConstants",
            "TuistLogging",
        ],
        path: "cli/Sources/TuistVersionCommand"
    ),
    .target(
        name: "TuistServer",
        dependencies: [
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            "TuistHTTP",
            "TuistThreadSafe",
            "TuistOpener",
            "TuistUniqueIDGenerator",
            fileSystemDependency,
            mockableDependency,
            pathDependency,
            swiftToolsSupportDependency,
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "apple.swift-http-types"),
            .product(name: "OpenAPIURLSession", package: "apple.swift-openapi-urlsession"),
            .product(name: "KeychainAccess", package: "kishikawakatsumi.KeychainAccess", condition: .when(platforms: [.macOS])),
            .product(name: "Rosalind", package: "tuist.Rosalind", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCore", condition: .when(platforms: [.macOS])),
            .target(name: "TuistProcess", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCI", condition: .when(platforms: [.macOS])),
            .target(name: "TuistAutomation", condition: .when(platforms: [.macOS])),
            .target(name: "TuistGit", condition: .when(platforms: [.macOS])),
            .target(name: "TuistXCActivityLog", condition: .when(platforms: [.macOS])),
            .target(name: "TuistXCResultService", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSimulator", condition: .when(platforms: [.macOS])),
            xcodeGraphDependency,
        ],
        path: "cli/Sources/TuistServer",
        exclude: ["OpenAPI/server.yml", "AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistOIDC",
        dependencies: [
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistOIDC",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistHTTP",
        dependencies: [
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            "TuistAlert",
            pathDependency,
            mockableDependency,
            fileSystemDependency,
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "apple.swift-http-types"),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            .target(name: "TuistHAR", condition: .when(platforms: [.macOS])),
        ],
        path: "cli/Sources/TuistHTTP",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistCAS",
        dependencies: [
            "TuistServer",
            "TuistHTTP",
            .product(name: "GRPCCore", package: "grpc.grpc-swift-2"),
            .product(name: "GRPCProtobuf", package: "grpc.grpc-swift-protobuf"),
            .product(name: "SwiftProtobuf", package: "apple.swift-protobuf"),
            .product(name: "libzstd", package: "facebook.zstd"),
            mockableDependency,
            pathDependency,
            .target(name: "TuistCache", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCASAnalytics", condition: .when(platforms: [.macOS])),
        ],
        path: "cli/Sources/TuistCAS",
        exclude: ["cas.proto", "keyvalue.proto", "grpc-swift-proto-generator-config.json", "AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistHAR",
        dependencies: [
            "TuistConstants",
            "TuistLogging",
            pathDependency,
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "apple.swift-http-types"),
        ],
        path: "cli/Sources/TuistHAR",
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    // MARK: Cross-platform test targets
    .testTarget(
        name: "TuistCASTests",
        dependencies: [
            "TuistCAS",
            "TuistEnvironment",
            "TuistServer",
            mockableDependency,
        ],
        path: "cli/Tests/TuistCASTests"
    ),
    .testTarget(
        name: "TuistOIDCTests",
        dependencies: [
            "TuistOIDC",
            "TuistEnvironment",
            "TuistEnvironmentTesting",
            mockableDependency,
        ],
        path: "cli/Tests/TuistOIDCTests"
    ),
    .testTarget(
        name: "TuistHTTPTests",
        dependencies: [
            "TuistHTTP",
            mockableDependency,
        ],
        path: "cli/Tests/TuistHTTPTests"
    ),
    .testTarget(
        name: "TuistUserInputReaderTests",
        dependencies: [
            "TuistUserInputReader",
        ],
        path: "cli/Tests/TuistUserInputReaderTests"
    ),
    .target(
        name: "TuistSupport",
        dependencies: [
            pathDependency,
            loggingDependency,
            swiftToolsSupportDependency,
            zipFoundationDependency,
            mockableDependency,
            fileSystemDependency,
            commandDependency,
            "TuistConstants",
            "TuistLogging",
            "TuistEnvironment",
            "TuistNooraExtension",
            "TuistAlert",
            "TuistThreadSafe",
            "TuistUserInputReader",
            .product(name: "Noora", package: "tuist.Noora"),
        ],
        path: "cli/Sources/TuistSupport",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
]

// MARK: - macOS-only targets

#if os(macOS)
targets.append(contentsOf: [
    .executableTarget(
        name: "tuistbenchmark",
        dependencies: [
            argumentParserDependency,
            pathDependency,
            swiftToolsSupportDependency,
            fileSystemDependency,
            "TuistSupport",
        ],
        path: "cli/Sources/tuistbenchmark",
        exclude: ["AGENTS.md"]
    ),
    .executableTarget(
        name: "tuistfixturegenerator",
        dependencies: [
            argumentParserDependency,
            pathDependency,
            swiftToolsSupportDependency,
            "ProjectDescription",
            "TuistSupport",
        ],
        path: "cli/Sources/tuistfixturegenerator",
        exclude: ["AGENTS.md"]
    ),
    .target(
        name: "TuistCore",
        dependencies: [
            pathDependency,
            "TuistSupport",
            xcodeGraphDependency,
            xcodeProjDependency,
            mockableDependency,
            fileSystemDependency,
            "TuistSimulator",
            .product(name: "XcodeMetadata", package: "tuist.XcodeGraph"),
            anyCodableDependency,
        ],
        path: "cli/Sources/TuistCore",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistKit",
        dependencies: [
            pathDependency,
            argumentParserDependency,
            mockableDependency,
            fileSystemDependency,
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            "TuistEnvKey",
            "TuistServer",
            "TuistOIDC",
            "TuistCacheCommand",
            "TuistAuthCommand",
            "TuistVersionCommand",
            .product(name: "Noora", package: "tuist.Noora"),
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            "TuistCAS",
            "TuistProcess",
            "TuistCore",
            "TuistSupport",
            "TuistGenerator",
            "TuistAutomation",
            "TuistLoader",
            "TuistHasher",
            "TuistScaffold",
            "TuistDependencies",
            "TuistMigration",
            "TuistPlugin",
            "TuistSimulator",
            "TuistCache",
            "TuistExtension",
            "TuistEncodable",
            "TuistRootDirectoryLocator",
            "TuistXcodeProjectOrWorkspacePathLocator",
            "TuistXCResultService",
            "TuistCI",
            "TuistLaunchctl",
            "ProjectDescription",
            "ProjectAutomation",
            xcodeProjDependency,
            graphVizDependency,
            xcodeGraphDependency,
            commandDependency,
            .product(name: "XcodeGraphMapper", package: "tuist.XcodeGraph"),
            anyCodableDependency,
            .product(name: "GRPCNIOTransportHTTP2", package: "grpc.grpc-swift-nio-transport"),
            .product(name: "MCP", package: "modelcontextprotocol.swift-sdk"),
            .product(name: "SwiftyJSON", package: "swiftyJSON.SwiftyJSON"),
            .product(name: "Rosalind", package: "tuist.Rosalind"),
        ],
        path: "cli/Sources/TuistKit",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "ProjectDescription",
        dependencies: [],
        path: "cli/Sources/ProjectDescription",
        exclude: ["AGENTS.md"]
    ),
    .target(
        name: "ProjectAutomation",
        path: "cli/Sources/ProjectAutomation",
        exclude: ["AGENTS.md"]
    ),
    .target(
        name: "TuistExtension",
        dependencies: [
            "TuistCache",
            "TuistCore",
            "TuistGenerator",
            "TuistHasher",
            "TuistServer",
            xcodeGraphDependency,
        ],
        path: "cli/Sources/TuistExtension"
    ),
    .target(
        name: "TuistTesting",
        dependencies: [
            "TuistSupport",
            "TuistServer",
            "TuistHTTP",
            "TuistAlert",
            "TuistEnvironmentTesting",
            xcodeGraphDependency,
            pathDependency,
            differenceDependency,
            fileSystemDependency,
            .product(name: "FileSystemTesting", package: "tuist.FileSystem"),
            argumentParserDependency,
        ],
        path: "cli/Sources/TuistTesting",
        exclude: ["AGENTS.md"],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistAcceptanceTesting",
        dependencies: [
            "TuistKit",
            "TuistCore",
            "TuistSupport",
            "TuistTesting",
            xcodeProjDependency,
            fileSystemDependency,
            "ProjectDescription",
            xcodeGraphDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistAcceptanceTesting",
        exclude: ["AGENTS.md"],
        linkerSettings: [.linkedFramework("XCTest")]
    ),
    .target(
        name: "TuistGenerator",
        dependencies: [
            xcodeProjDependency,
            pathDependency,
            "TuistCore",
            xcodeGraphDependency,
            "TuistSupport",
            graphVizDependency,
            mockableDependency,
            fileSystemDependency,
            stencilDependency,
            "TuistRootDirectoryLocator",
            "TuistLoader",
            "TuistServer",
            .product(name: "SwiftGenKit", package: "swiftGen.SwiftGen"),
            .product(name: "StencilSwiftKit", package: "swiftGen.StencilSwiftKit"),
        ],
        path: "cli/Sources/TuistGenerator",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistScaffold",
        dependencies: [
            pathDependency,
            "TuistCore",
            xcodeGraphDependency,
            "TuistSupport",
            stencilDependency,
            mockableDependency,
            fileSystemDependency,
            "TuistRootDirectoryLocator",
            .product(name: "StencilSwiftKit", package: "swiftGen.StencilSwiftKit"),
        ],
        path: "cli/Sources/TuistScaffold",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistAutomation",
        dependencies: [
            xcodeProjDependency,
            pathDependency,
            .product(name: "XcbeautifyLib", package: "cpisciotta.xcbeautify"),
            "TuistCore",
            xcodeGraphDependency,
            "TuistSupport",
            mockableDependency,
            fileSystemDependency,
            commandDependency,
        ],
        path: "cli/Sources/TuistAutomation",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistDependencies",
        dependencies: [
            "ProjectDescription",
            "TuistCore",
            xcodeGraphDependency,
            "TuistSupport",
            "TuistPlugin",
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistDependencies",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistMigration",
        dependencies: [
            "TuistCore",
            xcodeGraphDependency,
            "TuistSupport",
            xcodeProjDependency,
            mockableDependency,
            fileSystemDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistMigration",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistLoader",
        dependencies: [
            xcodeProjDependency,
            pathDependency,
            "TuistCore",
            xcodeGraphDependency,
            "TuistSupport",
            mockableDependency,
            "ProjectDescription",
            fileSystemDependency,
            "TuistRootDirectoryLocator",
            "TuistGit",
        ],
        path: "cli/Sources/TuistLoader",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistProcess",
        dependencies: [
            mockableDependency,
        ],
        path: "cli/Sources/TuistProcess",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistPlugin",
        dependencies: [
            xcodeGraphDependency,
            "TuistLoader",
            "TuistCore",
            "TuistSupport",
            "TuistScaffold",
            "TuistHTTP",
            mockableDependency,
            fileSystemDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistPlugin",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistHasher",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            fileSystemDependency,
            "TuistRootDirectoryLocator",
            pathDependency,
            xcodeGraphDependency,
            mockableDependency,
        ],
        path: "cli/Sources/TuistHasher",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistCache",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            "TuistHTTP",
            "TuistServer",
            fileSystemDependency,
            mockableDependency,
            pathDependency,
            xcodeGraphDependency,
            "TuistHasher",
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "apple.swift-openapi-urlsession"),
        ],
        path: "cli/Sources/TuistCache",
        exclude: ["OpenAPI/cache.yml", "AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistSimulator",
        dependencies: [
            xcodeGraphDependency,
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistSimulator",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
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
            fileSystemDependency,
            swiftToolsSupportDependency,
            pathDependency,
            .product(name: "XCLogParser", package: "MobileNativeFoundation.XCLogParser"),
        ],
        path: "cli/Sources/TuistXCActivityLog",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistXCResultService",
        dependencies: [
            "TuistSupport",
            "TuistXCActivityLog",
            commandDependency,
            fileSystemDependency,
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistXCResultService",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistGit",
        dependencies: [
            "TuistSupport",
            fileSystemDependency,
            swiftToolsSupportDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistGit",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistRootDirectoryLocator",
        dependencies: [
            "TuistCore",
            "TuistSupport",
            fileSystemDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistRootDirectoryLocator",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistXcodeProjectOrWorkspacePathLocator",
        dependencies: [
            "TuistSupport",
            fileSystemDependency,
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistXcodeProjectOrWorkspacePathLocator",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistCI",
        dependencies: [
            "TuistSupport",
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistCI",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistCASAnalytics",
        dependencies: [
            "TuistSupport",
            fileSystemDependency,
            pathDependency,
            mockableDependency,
        ],
        path: "cli/Sources/TuistCASAnalytics",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
    .target(
        name: "TuistLaunchctl",
        dependencies: [
            commandDependency,
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistLaunchctl",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug)),
        ]
    ),
])
#endif

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

// MARK: - Products

var products: [Product] = [
    .executable(name: "tuist", targets: ["tuist"]),
    .library(
        name: "TuistServer",
        targets: ["TuistServer"]
    ),
    .library(
        name: "TuistOIDC",
        targets: ["TuistOIDC"]
    ),
]

#if os(macOS)
products.append(contentsOf: [
    .executable(name: "tuistbenchmark", targets: ["tuistbenchmark"]),
    .executable(name: "tuistfixturegenerator", targets: ["tuistfixturegenerator"]),
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
        name: "TuistHasher",
        targets: ["TuistHasher"]
    ),
    .library(
        name: "TuistCache",
        targets: ["TuistCache"]
    ),
    .library(
        name: "TuistGenerator",
        targets: ["TuistGenerator"]
    ),
])
#endif

let package = Package(
    name: "tuist",
    platforms: [.macOS(.v15)],
    products: products,
    dependencies: [
        .package(id: "apple.swift-argument-parser", from: "1.5.0"),
        .package(id: "apple.swift-log", from: "1.5.3"),
        .package(id: "swiftlang.swift-tools-support-core", from: "0.6.1"),
        .package(id: "flight-school.AnyCodable", from: "0.6.7"),
        .package(id: "tuist.ZIPFoundation", from: "0.9.19"),
        .package(id: "kishikawakatsumi.KeychainAccess", from: "4.2.2"),
        .package(id: "stencilproject.Stencil", exact: "0.15.1"),
        .package(id: "tuist.GraphViz", exact: "0.4.2"),
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
        .package(id: "tuist.XcodeGraph", .upToNextMajor(from: "1.31.0")),
        .package(id: "tuist.FileSystem", .upToNextMajor(from: "0.14.11")),
        .package(id: "tuist.Command", .upToNextMajor(from: "0.8.0")),
        .package(id: "apple.swift-nio", from: "2.70.0"),
        .package(id: "crspybits.swift-log-file", .upToNextMajor(from: "0.1.0")),
        .package(id: "tuist.Noora", from: "0.54.0"),
        .package(
            id: "frazer-rbsn.OrderedSet", .upToNextMajor(from: "2.0.0")
        ),
        .package(id: "grpc.grpc-swift-2", from: "2.0.0"),
        .package(id: "apple.swift-protobuf", exact: "1.32.0"),
        .package(id: "grpc.grpc-swift-protobuf", from: "2.0.0"),
        .package(id: "grpc.grpc-swift-nio-transport", from: "2.0.0"),
        .package(id: "facebook.zstd", from: "1.5.0"),
        .package(id: "chrisaljoudi.swift-log-oslog", .upToNextMajor(from: "0.2.2")),
        .package(id: "MobileNativeFoundation.XCLogParser", .upToNextMajor(from: "0.2.45")),
        .package(id: "modelcontextprotocol.swift-sdk", .upToNextMajor(from: "0.9.0")),
        .package(id: "swiftyJSON.SwiftyJSON", .upToNextMajor(from: "5.0.2")),
        .package(id: "tuist.Rosalind", .upToNextMajor(from: "0.6.0")),
        .package(id: "swiftGen.StencilSwiftKit", exact: "2.10.1"),
        .package(id: "swiftGen.SwiftGen", exact: "6.6.2"),
        .package(id: "sparkle-project.Sparkle", from: "2.6.4"),
        .package(id: "kean.Nuke", .upToNextMajor(from: "12.8.0")),
        .package(
            url: "https://github.com/lfroms/fluid-menu-bar-extra",
            .upToNextMajor(from: "1.1.0")
        ),
        .package(id: "tuist.sdk", .upToNextMajor(from: "0.2.0")),
        .package(id: "apple.swift-collections", "1.1.4"..<"1.3.0"),
        .package(id: "apple.swift-service-context", .upToNextMajor(from: "1.0.0")),
        .package(id: "pointfreeco.swift-snapshot-testing", .upToNextMajor(from: "1.18.1")),
        .package(id: "leif-ibsen.SwiftECC", exact: "5.5.0"),
    ],
    targets: targets,
    swiftLanguageModes: [.v5]
)
