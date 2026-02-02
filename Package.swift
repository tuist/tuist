// swift-tools-version: 6.1

@preconcurrency import PackageDescription

// macOS-only packages that don't compile on Linux (have Obj-C code or macOS-only APIs)
#if os(macOS)
let macOSOnlyPackages: [Package.Dependency] = [
    .package(id: "sparkle-project.Sparkle", from: "2.6.4"),
    .package(
        id: "chrisaljoudi.swift-log-oslog",
        .upToNextMajor(from: "0.2.2")
    ),
    .package(
        id: "MobileNativeFoundation.XCLogParser",
        .upToNextMajor(from: "0.2.45")
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
    .package(
        url: "https://github.com/lfroms/fluid-menu-bar-extra",
        .upToNextMajor(from: "1.1.0")
    ),
    .package(id: "tuist.sdk", .upToNextMajor(from: "0.2.0")),
    // SwiftGen depends on XCGLogger which has Obj-C code
    .package(id: "swiftGen.StencilSwiftKit", exact: "2.10.1"),
    .package(id: "swiftGen.SwiftGen", exact: "6.6.2"),
    // swift-log-file depends on XCGLogger which has Obj-C code
    .package(id: "crspybits.swift-log-file", .upToNextMajor(from: "0.1.0")),
]
#else
let macOSOnlyPackages: [Package.Dependency] = []
#endif

let swiftToolsSupportDependency: Target.Dependency = .product(
    name: "SwiftToolsSupport-auto", package: "swiftlang.swift-tools-support-core"
)
let pathDependency: Target.Dependency = .product(name: "Path", package: "Path")
let loggingDependency: Target.Dependency = .product(name: "Logging", package: "apple.swift-log")
let argumentParserDependency: Target.Dependency = .product(
    name: "ArgumentParser", package: "apple.swift-argument-parser"
)
let fileSystemDependency: Target.Dependency = .product(name: "FileSystem", package: "FileSystem")
let commandDependency: Target.Dependency = .product(name: "Command", package: "Command")
let xcodeGraphDependency: Target.Dependency = .product(name: "XcodeGraph", package: "tuist.XcodeGraph")
let xcodeProjDependency: Target.Dependency = .product(name: "XcodeProj", package: "tuist.XcodeProj")
let mockableDependency: Target.Dependency = .product(name: "Mockable", package: "kolos65.Mockable")
let zipFoundationDependency: Target.Dependency = .product(name: "ZIPFoundation", package: "tuist.ZIPFoundation")
let stencilDependency: Target.Dependency = .product(name: "Stencil", package: "stencilproject.Stencil")
let graphVizDependency: Target.Dependency = .product(name: "GraphViz", package: "tuist.GraphViz")
let differenceDependency: Target.Dependency = .product(name: "Difference", package: "krzysztofzablocki.Difference")
let anyCodableDependency: Target.Dependency = .product(name: "AnyCodable", package: "flight-school.AnyCodable")

// macOS-only target dependencies (empty arrays on other platforms)
#if os(macOS)
let tuistKitMacOSDependencies: [Target.Dependency] = [
    .product(name: "MCP", package: "modelcontextprotocol.swift-sdk"),
    .product(name: "SwiftyJSON", package: "swiftyJSON.SwiftyJSON"),
    .product(name: "Rosalind", package: "tuist.Rosalind"),
]
let tuistSupportMacOSDependencies: [Target.Dependency] = [
    .product(name: "LoggingOSLog", package: "chrisaljoudi.swift-log-oslog"),
    .product(name: "FileLogging", package: "crspybits.swift-log-file"),
]
let tuistServerMacOSDependencies: [Target.Dependency] = [
    .product(name: "Rosalind", package: "tuist.Rosalind"),
]
let tuistXCActivityLogMacOSDependencies: [Target.Dependency] = [
    .product(name: "XCLogParser", package: "MobileNativeFoundation.XCLogParser"),
]
let tuistGeneratorMacOSDependencies: [Target.Dependency] = [
    .product(name: "SwiftGenKit", package: "swiftGen.SwiftGen"),
    .product(name: "StencilSwiftKit", package: "swiftGen.StencilSwiftKit"),
]
let tuistScaffoldMacOSDependencies: [Target.Dependency] = [
    .product(name: "StencilSwiftKit", package: "swiftGen.StencilSwiftKit"),
]
#else
let tuistKitMacOSDependencies: [Target.Dependency] = []
let tuistSupportMacOSDependencies: [Target.Dependency] = []
let tuistServerMacOSDependencies: [Target.Dependency] = []
let tuistXCActivityLogMacOSDependencies: [Target.Dependency] = []
let tuistGeneratorMacOSDependencies: [Target.Dependency] = []
let tuistScaffoldMacOSDependencies: [Target.Dependency] = []
#endif

let targets: [Target] = [
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
            .define("MOCKING", .when(configuration: .debug))
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
            "TuistServer",
            "TuistOIDC",
            .product(name: "Noora", package: "tuist.Noora"),
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            // macOS-only dependencies
            .target(name: "TuistCAS", condition: .when(platforms: [.macOS])),
            .target(name: "TuistProcess", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCore", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            .target(name: "TuistGenerator", condition: .when(platforms: [.macOS])),
            .target(name: "TuistAutomation", condition: .when(platforms: [.macOS])),
            .target(name: "TuistLoader", condition: .when(platforms: [.macOS])),
            .target(name: "TuistHasher", condition: .when(platforms: [.macOS])),
            .target(name: "TuistScaffold", condition: .when(platforms: [.macOS])),
            .target(name: "TuistDependencies", condition: .when(platforms: [.macOS])),
            .target(name: "TuistMigration", condition: .when(platforms: [.macOS])),
            .target(name: "TuistPlugin", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSimulator", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCache", condition: .when(platforms: [.macOS])),
            .target(name: "TuistRootDirectoryLocator", condition: .when(platforms: [.macOS])),
            .target(name: "TuistXcodeProjectOrWorkspacePathLocator", condition: .when(platforms: [.macOS])),
            .target(name: "TuistXCResultService", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCI", condition: .when(platforms: [.macOS])),
            .target(name: "TuistLaunchctl", condition: .when(platforms: [.macOS])),
            .product(name: "XcodeProj", package: "tuist.XcodeProj", condition: .when(platforms: [.macOS])),
            .product(name: "GraphViz", package: "tuist.GraphViz", condition: .when(platforms: [.macOS])),
            .product(name: "XcodeGraph", package: "tuist.XcodeGraph", condition: .when(platforms: [.macOS])),
            .product(name: "Command", package: "Command", condition: .when(platforms: [.macOS])),
            .product(name: "XcodeGraphMapper", package: "tuist.XcodeGraph", condition: .when(platforms: [.macOS])),
            .product(name: "AnyCodable", package: "flight-school.AnyCodable", condition: .when(platforms: [.macOS])),
            .product(name: "GRPCNIOTransportHTTP2", package: "grpc.grpc-swift-nio-transport", condition: .when(platforms: [.macOS])),
            .target(name: "ProjectDescription", condition: .when(platforms: [.macOS])),
            .target(name: "ProjectAutomation", condition: .when(platforms: [.macOS])),
        ] + tuistKitMacOSDependencies,
        path: "cli/Sources/TuistKit",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .executableTarget(
        name: "tuist",
        dependencies: [
            .target(name: "TuistKit", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            .target(name: "TuistLoader", condition: .when(platforms: [.macOS])),
            "TuistCacheConfigCommand",
            "TuistAuthLoginCommand",
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            argumentParserDependency,
            .target(name: "ProjectDescription", condition: .when(platforms: [.macOS])),
            .target(name: "ProjectAutomation", condition: .when(platforms: [.macOS])),
            .product(name: "Noora", package: "tuist.Noora"),
            pathDependency,
            swiftToolsSupportDependency,
        ],
        path: "cli/Sources/tuist",
        exclude: ["AGENTS.md"]
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
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistLogging",
        dependencies: [
            loggingDependency,
            "TuistEnvironment",
        ],
        path: "cli/Sources/TuistLogging"
    ),
    .target(
        name: "TuistCacheConfigCommand",
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
        ],
        path: "cli/Sources/TuistCacheConfigCommand"
    ),
    .target(
        name: "TuistAuthLoginCommand",
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
        ],
        path: "cli/Sources/TuistAuthLoginCommand"
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
            .product(name: "Noora", package: "tuist.Noora"),
            .product(name: "OrderedSet", package: "frazer-rbsn.OrderedSet"),
        ] + tuistSupportMacOSDependencies,
        path: "cli/Sources/TuistSupport",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistTesting",
        dependencies: [
            "TuistSupport",
            "TuistServer",
            "TuistHTTP",
            xcodeGraphDependency,
            pathDependency,
            differenceDependency,
            fileSystemDependency,
            .product(name: "FileSystemTesting", package: "FileSystem"),
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
        ] + tuistGeneratorMacOSDependencies,
        path: "cli/Sources/TuistGenerator",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
        ] + tuistScaffoldMacOSDependencies,
        path: "cli/Sources/TuistScaffold",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistProcess",
        dependencies: [
            mockableDependency
        ],
        path: "cli/Sources/TuistProcess",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistServer",
        dependencies: [
            .target(name: "TuistCore", condition: .when(platforms: [.macOS])),
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            "TuistHTTP",
            .target(name: "TuistXCActivityLog", condition: .when(platforms: [.macOS])),
            .target(name: "TuistXCResultService", condition: .when(platforms: [.macOS])),
            fileSystemDependency,
            xcodeGraphDependency,
            mockableDependency,
            .product(name: "KeychainAccess", package: "kishikawakatsumi.KeychainAccess", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCI", condition: .when(platforms: [.macOS])),
            .target(name: "TuistProcess", condition: .when(platforms: [.macOS])),
            pathDependency,
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "apple.swift-http-types"),
            .product(name: "OpenAPIURLSession", package: "apple.swift-openapi-urlsession"),
        ] + tuistServerMacOSDependencies,
        path: "cli/Sources/TuistServer",
        exclude: ["OpenAPI/server.yml", "AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistOIDC",
        dependencies: [
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistOIDC",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistHTTP",
        dependencies: [
            .target(name: "TuistSupport", condition: .when(platforms: [.macOS])),
            "TuistConstants",
            "TuistEnvironment",
            "TuistLogging",
            pathDependency,
            mockableDependency,
            .product(name: "OpenAPIRuntime", package: "apple.swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "apple.swift-http-types"),
        ],
        path: "cli/Sources/TuistHTTP",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            fileSystemDependency,
            swiftToolsSupportDependency,
            pathDependency,
        ] + tuistXCActivityLogMacOSDependencies,
        path: "cli/Sources/TuistXCActivityLog",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
        ]
    ),
    .target(
        name: "TuistXCResultService",
        dependencies: [
            "TuistSupport",
            .target(name: "TuistXCActivityLog", condition: .when(platforms: [.macOS])),
            .product(name: "Command", package: "Command"),
            fileSystemDependency,
            mockableDependency,
            pathDependency,
        ],
        path: "cli/Sources/TuistXCResultService",
        exclude: ["AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            // macOS-only dependencies
            .target(name: "TuistCache", condition: .when(platforms: [.macOS])),
            .target(name: "TuistRootDirectoryLocator", condition: .when(platforms: [.macOS])),
            .target(name: "TuistCASAnalytics", condition: .when(platforms: [.macOS])),
        ],
        path: "cli/Sources/TuistCAS",
        exclude: ["cas.proto", "keyvalue.proto", "grpc-swift-proto-generator-config.json", "AGENTS.md"],
        swiftSettings: [
            .define("MOCKING", .when(configuration: .debug))
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
            .define("MOCKING", .when(configuration: .debug))
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
            name: "TuistOIDC",
            targets: ["TuistOIDC"]
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
        .package(url: "https://github.com/tuist/Path.git", .upToNextMajor(from: "0.3.0")),
        .package(id: "tuist.XcodeGraph", .upToNextMajor(from: "1.31.0")),
        .package(url: "https://github.com/tuist/FileSystem.git", .upToNextMajor(from: "0.14.11")),
        .package(url: "https://github.com/tuist/Command.git", .upToNextMajor(from: "0.8.0")),
        // swift-collections 1.3.0 requires Swift 6.2.0
        .package(id: "apple.swift-collections", "1.1.4"..<"1.3.0"),
        .package(
            id: "apple.swift-service-context", .upToNextMajor(from: "1.0.0")
        ),
        .package(id: "apple.swift-nio", from: "2.70.0"),
        .package(id: "tuist.Noora", from: "0.54.0"),
        .package(
            id: "frazer-rbsn.OrderedSet", .upToNextMajor(from: "2.0.0")
        ),
        .package(
            id: "pointfreeco.swift-snapshot-testing",
            .upToNextMajor(from: "1.18.1")
        ),
        .package(id: "leif-ibsen.SwiftECC", exact: "5.5.0"),
        .package(id: "grpc.grpc-swift-2", from: "2.0.0"),
        .package(id: "apple.swift-protobuf", exact: "1.32.0"),
        .package(id: "grpc.grpc-swift-protobuf", from: "2.0.0"),
        .package(id: "grpc.grpc-swift-nio-transport", from: "2.0.0"),
        .package(id: "facebook.zstd", from: "1.5.0"),
    ] + macOSOnlyPackages,
    targets: targets,
    swiftLanguageModes: [.v5]
)
