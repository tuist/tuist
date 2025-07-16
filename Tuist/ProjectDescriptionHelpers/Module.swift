import Foundation
import ProjectDescription

public enum Module: String, CaseIterable {
    case tuist
    case tuistBenchmark = "tuistbenchmark"
    case tuistFixtureGenerator = "tuistfixturegenerator"
    case projectDescription = "ProjectDescription"
    case projectAutomation = "ProjectAutomation"
    case acceptanceTesting = "TuistAcceptanceTesting"
    case testing = "TuistTesting"
    case support = "TuistSupport"
    case kit = "TuistKit"
    case core = "TuistCore"
    case generator = "TuistGenerator"
    case scaffold = "TuistScaffold"
    case loader = "TuistLoader"
    case asyncQueue = "TuistAsyncQueue"
    case plugin = "TuistPlugin"
    case analytics = "TuistAnalytics"
    case migration = "TuistMigration"
    case dependencies = "TuistDependencies"
    case automation = "TuistAutomation"
    case server = "TuistServer"
    case hasher = "TuistHasher"
    case cache = "TuistCache"
    case simulator = "TuistSimulator"
    case xcActivityLog = "TuistXCActivityLog"
    case git = "TuistGit"
    case rootDirectoryLocator = "TuistRootDirectoryLocator"

    private static func cacheEEDirectory() -> URL {
        let currentFileURL = URL(fileURLWithPath: #file)
        return
            currentFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cli")
            .appendingPathComponent("TuistCacheEE")
    }

    private static func includeEE() -> Bool {
        if case let .string(value) = Environment.ee {
            return value == "1"
        } else {
            return false
        }
    }

    public static func allTargets() -> [Target] {
        var targets = Module.allCases.flatMap(\.targets)
        targets.append(contentsOf: cacheEETargets())
        return targets
    }

    public static func cacheEETargets() -> [Target] {
        guard includeEE() else { return [] }

        return [
            .target(
                name: "TuistCacheEE",
                destinations: [.mac],
                product: .staticFramework,
                bundleId: "dev.tuist.TuistCacheEE",
                deploymentTargets: .macOS("14.0"),
                infoPlist: .default,
                sources: ["\(cacheEEDirectory().path())/Sources/**/*.swift"],
                dependencies: [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.server.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "Path"),
                    .external(name: "FileSystem"),
                    .external(name: "SwiftECC"),
                ],
                settings: .settings(
                    configurations: [
                        .debug(
                            name: "Debug",
                            settings: [
                                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MOCKING"
                            ],
                            xcconfig: nil
                        ),
                        .release(
                            name: "Release",
                            settings: [:],
                            xcconfig: nil
                        ),
                    ]
                )
            ),
            .target(
                name: "TuistCacheEETests",
                destinations: [.mac],
                product: .unitTests,
                bundleId: "dev.tuist.TuistCacheEETests",
                deploymentTargets: .macOS("14.0"),
                infoPlist: .default,
                sources: ["\(cacheEEDirectory().path())/Tests/**/*.swift"],
                dependencies: [
                    .target(name: "TuistCacheEE")
                ]
            ),

        ]
    }

    public var isRunnable: Bool {
        switch self {
        case .tuistFixtureGenerator, .tuist, .tuistBenchmark:
            return true
        default:
            return false
        }
    }

    public var acceptanceTestTargets: [Target] {
        var targets: [Target] = []

        if let acceptanceTestsTargetName {
            targets.append(
                target(
                    name: acceptanceTestsTargetName,
                    product: .unitTests,
                    dependencies: acceptanceTestDependencies,
                    isTestingTarget: false
                )
            )
        }

        return targets
    }

    public var unitTestTargets: [Target] {
        var targets: [Target] = []

        if let unitTestsTargetName {
            targets.append(
                target(
                    name: unitTestsTargetName,
                    product: .unitTests,
                    dependencies: unitTestDependencies,
                    isTestingTarget: false
                )
            )
        }

        return targets
    }

    public var testTargets: [Target] {
        return unitTestTargets + acceptanceTestTargets
    }

    public var targets: [Target] {
        let targets: [Target] = sourceTargets
        return targets + testTargets
    }

    public var sourceTargets: [Target] {
        let isStaticProduct = product == .staticLibrary || product == .staticFramework
        let isTestingTarget = targetName == Module.acceptanceTesting.targetName
        return [
            target(
                name: targetName,
                product: product,
                dependencies: dependencies + (isStaticProduct ? [.external(name: "Mockable")] : []),
                isTestingTarget: isTestingTarget
            )
        ]
    }

    fileprivate var sharedDependencies: [TargetDependency] {
        return [
            .external(name: "Path"),
            .external(name: "SystemPackage"),
        ]
    }

    public var acceptanceTestsTargetName: String? {
        switch self {
        case .kit, .automation, .dependencies, .generator:
            return "\(rawValue)AcceptanceTests"
        default:
            return nil
        }
    }

    public var unitTestsTargetName: String? {
        switch self {
        case .analytics, .tuist, .tuistBenchmark, .tuistFixtureGenerator, .projectAutomation,
            .projectDescription,
            .acceptanceTesting, .simulator, .testing:
            return nil
        default:
            return "\(rawValue)Tests"
        }
    }

    public var targetName: String {
        rawValue
    }

    public var product: Product {
        switch self {
        case .tuist, .tuistBenchmark, .tuistFixtureGenerator:
            return .commandLineTool
        case .projectAutomation, .projectDescription:
            return .framework
        default:
            return .staticFramework
        }
    }

    public var acceptanceTestDependencies: [TargetDependency] {
        let dependencies: [TargetDependency] =
            switch self {
            case .generator:
                [
                    .target(name: Module.support.targetName),
                    .target(name: Module.acceptanceTesting.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "XcodeProj"),
                ]
            case .automation:
                [
                    .target(name: Module.acceptanceTesting.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.kit.targetName),
                    .target(name: Module.support.targetName),
                ]
            case .dependencies:
                [
                    .target(name: Module.acceptanceTesting.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.kit.targetName),
                    .external(name: "XcodeProj"),
                    .external(name: "Command"),
                ]
            case .kit:
                [
                    .target(name: Module.acceptanceTesting.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.kit.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.server.targetName),
                    .target(name: Module.core.targetName),
                    .external(name: "XcodeProj"),
                ]
            default:
                []
            }
        return dependencies + [.external(name: "SnapshotTesting")] + sharedDependencies
    }

    public var strictConcurrencySetting: String? {
        switch self {
        case .projectAutomation, .projectDescription:
            return "complete"
        case .support:
            return "targeted"
        default:
            return nil
        }
    }

    public var dependencies: [TargetDependency] {
        var dependencies: [TargetDependency] =
            switch self {
            case .testing:
                [
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.core.targetName),
                    .target(name: Module.server.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "Difference"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "FileSystem"),
                    .external(name: "FileSystemTesting"),
                    .external(name: "Command"),
                    .external(name: "Logging"),
                    .external(name: "ArgumentParser"),
                    .xctest,
                ]
            case .acceptanceTesting:
                [
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.kit.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.core.targetName),
                    .external(name: "XcodeProj"),
                    .external(name: "XcodeGraph"),
                    .external(name: "FileSystem"),
                ]
            case .tuist:
                [
                    .target(name: Module.support.targetName),
                    .target(name: Module.loader.targetName),
                    .target(name: Module.kit.targetName),
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.automation.targetName),
                    .external(name: "GraphViz"),
                    .external(name: "ArgumentParser"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "Noora"),
                ]
            case .tuistBenchmark:
                [
                    .target(name: Module.support.targetName),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "ArgumentParser"),
                    .external(name: "FileSystem"),
                ]
            case .tuistFixtureGenerator:
                [
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.support.targetName),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "ArgumentParser"),
                ]
            case .projectAutomation, .projectDescription:
                []
            case .support:
                [
                    .target(name: Module.projectDescription.targetName),
                    .external(name: "FileSystem"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "AnyCodable"),
                    .external(name: "XcodeProj"),
                    .external(name: "Logging"),
                    .external(name: "ZIPFoundation"),
                    .external(name: "Difference"),
                    .external(name: "Command"),
                    .external(name: "FileLogging"),
                    .external(name: "LoggingOSLog"),
                    .external(name: "Noora"),
                    .external(name: "XCLogParser"),
                    .external(name: "OrderedSet"),
                ]
            case .kit:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.hasher.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.generator.targetName),
                    .target(name: Module.automation.targetName),
                    .target(name: Module.server.targetName),
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.projectAutomation.targetName),
                    .target(name: Module.loader.targetName),
                    .target(name: Module.scaffold.targetName),
                    .target(name: Module.dependencies.targetName),
                    .target(name: Module.migration.targetName),
                    .target(name: Module.asyncQueue.targetName),
                    .target(name: Module.analytics.targetName),
                    .target(name: Module.plugin.targetName),
                    .target(name: Module.cache.targetName),
                    .target(name: Module.simulator.targetName),
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .external(name: "MCP"),
                    .external(name: "FileSystem"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "XcodeGraph"),
                    .external(name: "XcodeGraphMapper"),
                    .external(name: "ArgumentParser"),
                    .external(name: "GraphViz"),
                    .external(name: "AnyCodable"),
                    .external(name: "OpenAPIRuntime"),
                    .external(name: "XCResultKit"),
                    .external(name: "Noora"),
                    .external(name: "SwiftyJSON"),
                    .external(name: "Rosalind"),
                ] + (Self.includeEE() ? [.target(name: "TuistCacheEE")] : [])
            case .core:
                [
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.simulator.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "XcodeProj"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "AnyCodable"),
                    .external(name: "Command"),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeMetadata"),
                ]
            case .generator:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeGraph"),
                    .external(name: "SwiftGenKit"),
                    .external(name: "PathKit"),
                    .external(name: "StencilSwiftKit"),
                    .external(name: "XcodeProj"),
                    .external(name: "GraphViz"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "Stencil"),
                ]
            case .scaffold:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeGraph"),
                    .external(name: "PathKit"),
                    .external(name: "StencilSwiftKit"),
                ]
            case .loader:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.git.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeProj"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "_NIOFileSystem"),
                ]
            case .asyncQueue:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeGraph"),
                    .external(name: "Queuer"),
                    .external(name: "XcodeProj"),
                ]
            case .plugin:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.loader.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.scaffold.targetName),
                    .external(name: "FileSystem"),
                    .external(name: "SwiftToolsSupport"),
                ]
            case .analytics:
                [
                    .target(name: Module.asyncQueue.targetName),
                    .target(name: Module.core.targetName),
                    .target(name: Module.loader.targetName),
                    .target(name: Module.support.targetName),
                    .external(name: "AnyCodable"),
                    .external(name: "XcodeGraph"),
                ]
            case .migration:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .external(name: "PathKit"),
                    .external(name: "XcodeProj"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "XcodeGraph"),
                    .external(name: "FileSystem"),
                ]
            case .dependencies:
                [
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .external(name: "XcodeGraph"),
                ]
            case .automation:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.simulator.targetName),
                    .external(name: "Command"),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeProj"),
                    .external(name: "XcbeautifyLib"),
                    .external(name: "XcodeGraph"),
                    .external(name: "SwiftToolsSupport"),
                ]
            case .server:
                [
                    .target(name: Module.support.targetName, condition: .when([.macos])),
                    .target(name: Module.core.targetName, condition: .when([.macos])),
                    .target(name: Module.cache.targetName, condition: .when([.macos])),
                    .target(name: Module.xcActivityLog.targetName, condition: .when([.macos])),
                    .target(name: Module.simulator.targetName),
                    .target(name: Module.automation.targetName, condition: .when([.macos])),
                    .external(name: "FileSystem"),
                    .external(name: "OpenAPIRuntime"),
                    .external(name: "OpenAPIURLSession"),
                    .external(name: "HTTPTypes"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "XcodeGraph"),
                    .external(name: "Rosalind", condition: .when([.macos])),
                    .external(name: "KeychainAccess"),
                ]
            case .hasher:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .external(name: "XcodeGraph"),
                ]
            case .cache:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.hasher.targetName),
                    .external(name: "XcodeGraph"),
                ]
            case .simulator:
                [
                    .external(name: "XcodeGraph")
                ]
            case .xcActivityLog:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .target(name: Module.git.targetName),
                    .external(name: "FileSystem"),
                    .external(name: "XCLogParser"),
                    .external(name: "SwiftToolsSupport"),
                ]
            case .rootDirectoryLocator:
                [
                    .target(name: Module.support.targetName),
                    .target(name: Module.core.targetName),
                    .external(name: "FileSystem"),
                ]
            case .git:
                [
                    .target(name: Module.support.targetName),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "FileSystem"),
                ]
            }
        if self != .projectDescription, self != .projectAutomation {
            dependencies.append(contentsOf: sharedDependencies)
        }
        return dependencies
    }

    public var unitTestDependencies: [TargetDependency] {
        var dependencies: [TargetDependency] =
            switch self {
            case .tuist, .tuistBenchmark, .acceptanceTesting, .simulator, .testing:
                []
            case .tuistFixtureGenerator:
                [
                    .target(name: Module.projectDescription.targetName)
                ]
            case .support:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "FileSystem"),
                    .external(name: "Command"),
                ]
            case .projectDescription:
                [
                    .target(name: Module.testing.targetName),
                    .target(name: Module.support.targetName),
                ]
            case .projectAutomation:
                []
            case .kit:
                [
                    .target(name: Module.support.targetName),
                    .target(name: Module.automation.targetName),
                    .target(name: Module.cache.targetName),
                    .target(name: Module.server.targetName),
                    .target(name: Module.scaffold.targetName),
                    .target(name: Module.analytics.targetName),
                    .target(name: Module.loader.targetName),
                    .target(name: Module.core.targetName),
                    .target(name: Module.generator.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.projectAutomation.targetName),
                    .target(name: Module.migration.targetName),
                    .target(name: Module.asyncQueue.targetName),
                    .target(name: Module.plugin.targetName),
                    .target(name: Module.git.targetName),
                    .external(name: "ArgumentParser"),
                    .external(name: "GraphViz"),
                    .external(name: "AnyCodable"),
                    .external(name: "Difference"),
                    .external(name: "XcodeProj"),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeGraph"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "FileSystemTesting"),
                ]
            case .core:
                [
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "FileSystem"),
                ]
            case .generator:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.loader.targetName),
                    .external(name: "PathKit"),
                    .external(name: "XcodeProj"),
                    .external(name: "GraphViz"),
                    .external(name: "XcodeGraph"),
                    .external(name: "SwiftToolsSupport"),
                ]
            case .scaffold:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "FileSystem"),
                ]
            case .loader:
                [
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "FileSystem"),
                    .external(name: "XcodeGraph"),
                    .external(name: "_NIOFileSystem"),
                ]
            case .asyncQueue:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "Queuer"),
                ]
            case .plugin:
                [
                    .target(name: Module.projectDescription.targetName),
                    .target(name: Module.core.targetName),
                    .target(name: Module.scaffold.targetName),
                    .target(name: Module.loader.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "SwiftToolsSupport"),
                ]
            case .analytics:
                [
                    .target(name: Module.testing.targetName)
                ]
            case .migration:
                [
                    .target(name: Module.testing.targetName)
                ]
            case .dependencies:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.loader.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "XcodeGraph"),
                ]
            case .automation:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "FileSystem"),
                    .external(name: "SwiftToolsSupport"),
                    .external(name: "Command"),
                    .external(name: "FileSystemTesting"),
                ]
            case .server:
                [
                    .target(name: Module.support.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.core.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "OpenAPIRuntime"),
                    .external(name: "HTTPTypes"),
                    .external(name: "FileSystem"),
                    .external(name: "SwiftToolsSupport"),
                ]
            case .hasher:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.support.targetName),
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .target(name: Module.testing.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "FileSystem"),
                ]
            case .cache:
                [
                    .target(name: Module.core.targetName),
                    .target(name: Module.hasher.targetName),
                    .target(name: Module.testing.targetName),
                    .target(name: Module.support.targetName),
                    .external(name: "XcodeGraph"),
                    .external(name: "SwiftToolsSupport"),
                ]
            case .xcActivityLog:
                [
                    .target(name: Module.rootDirectoryLocator.targetName),
                    .target(name: Module.testing.targetName),
                ]
            case .rootDirectoryLocator:
                [
                    .target(name: Module.testing.targetName)
                ]
            case .git:
                [
                    .target(name: Module.testing.targetName)
                ]
            }
        dependencies =
            dependencies + sharedDependencies + [
                .target(name: targetName), .external(name: "Mockable"),
                .external(name: "SnapshotTesting"),
            ]

        return dependencies
    }

    private var destinations: Destinations {
        switch self {
        case .simulator, .server:
            [.mac, .iPhone, .iPad]
        default:
            [.mac]
        }
    }

    private var deploymentTargets: DeploymentTargets {
        switch self {
        case .simulator, .server: .multiplatform(iOS: "18.0", macOS: "14.0")
        default: .macOS("14.0")
        }
    }

    fileprivate func target(
        name: String,
        product: Product,
        dependencies: [TargetDependency],
        isTestingTarget: Bool
    ) -> Target {
        var debugSettings: ProjectDescription.SettingsDictionary = [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MOCKING"
        ]
        var releaseSettings: ProjectDescription.SettingsDictionary = [:]
        if isTestingTarget {
            debugSettings["ENABLE_TESTING_SEARCH_PATHS"] = "YES"
            releaseSettings["ENABLE_TESTING_SEARCH_PATHS"] = "YES"
        }

        if let strictConcurrencySetting, product == .framework {
            debugSettings["SWIFT_STRICT_CONCURRENCY"] = .string(strictConcurrencySetting)
            releaseSettings["SWIFT_STRICT_CONCURRENCY"] = .string(strictConcurrencySetting)
        }

        let rootFolder: String
        switch product {
        case .unitTests:
            rootFolder = "cli/Tests"
            debugSettings["CODE_SIGN_IDENTITY"] = ""
        default:
            rootFolder = "cli/Sources"
        }

        var baseSettings = settings.base
        baseSettings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"

        let settings = Settings.settings(
            base: baseSettings,
            configurations: [
                .debug(
                    name: "Debug",
                    settings: debugSettings,
                    xcconfig: nil
                ),
                .release(
                    name: "Release",
                    settings: releaseSettings,
                    xcconfig: nil
                ),
            ]
        )

        let destinations: Destinations =
            switch product {
            case .framework, .staticFramework: destinations
            default: [.mac]
            }

        let deploymentTargets: DeploymentTargets =
            switch product {
            case .framework, .staticFramework: deploymentTargets
            default: .macOS("14.0")
            }

        return .target(
            name: name,
            destinations: destinations,
            product: product,
            bundleId: "dev.tuist.\(name)",
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: ["\(rootFolder)/\(name)/**/*.swift"],
            dependencies: dependencies,
            settings: settings
        )
    }

    fileprivate var settings: Settings {
        switch self {
        case .tuist:
            return .settings(
                base: [
                    "LD_RUNPATH_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)"
                ],
                configurations: [
                    .debug(name: "Debug", settings: [:], xcconfig: nil),
                    .release(name: "Release", settings: [:], xcconfig: nil),
                ]
            )
        case .projectDescription, .projectAutomation:
            return .settings(
                base: ["BUILD_LIBRARY_FOR_DISTRIBUTION": "YES"],
                configurations: [
                    .debug(
                        name: "Debug",
                        settings: [:],
                        xcconfig: nil
                    ),
                    .release(
                        name: "Release",
                        settings: [:],
                        xcconfig: nil
                    ),
                ]
            )
        default:
            return .settings(
                configurations: [
                    .debug(
                        name: "Debug",
                        settings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MOCKING"],
                        xcconfig: nil
                    ),
                    .release(
                        name: "Release",

                        settings: [:],
                        xcconfig: nil
                    ),
                ]
            )
        }
    }
}
