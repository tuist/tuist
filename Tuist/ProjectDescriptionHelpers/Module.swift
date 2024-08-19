import Foundation
import ProjectDescription

public enum Module: String, CaseIterable {
    case tuist
    case tuistBenchmark = "tuistbenchmark"
    case tuistFixtureGenerator = "tuistfixturegenerator"
    case projectDescription = "ProjectDescription"
    case projectAutomation = "ProjectAutomation"
    case acceptanceTesting = "TuistAcceptanceTesting"
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
            targets.append(target(
                name: acceptanceTestsTargetName,
                product: .unitTests,
                dependencies: acceptanceTestDependencies,
                isTestingTarget: false
            ))
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

        if let integrationTestsTargetName {
            targets.append(
                target(
                    name: integrationTestsTargetName,
                    product: .unitTests,
                    dependencies: integrationTestsDependencies,
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
        var targets: [Target] = sourceTargets

        if let testingTargetName {
            targets.append(
                target(
                    name: testingTargetName,
                    product: product,
                    dependencies: testingDependencies,
                    isTestingTarget: true
                )
            )
        }

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
            ),
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

    public var testingTargetName: String? {
        switch self {
        case .tuist, .tuistBenchmark, .tuistFixtureGenerator, .kit, .projectAutomation, .projectDescription, .analytics,
             .dependencies, .acceptanceTesting, .server, .hasher, .cache:
            return nil
        default:
            return "\(rawValue)Testing"
        }
    }

    public var unitTestsTargetName: String? {
        switch self {
        case .analytics, .tuist, .tuistBenchmark, .tuistFixtureGenerator, .projectAutomation, .projectDescription,
             .acceptanceTesting:
            return nil
        default:
            return "\(rawValue)Tests"
        }
    }

    public var integrationTestsTargetName: String? {
        switch self {
        case .tuist, .tuistBenchmark, .tuistFixtureGenerator, .projectAutomation, .projectDescription,
             .asyncQueue,
             .plugin, .analytics, .dependencies, .acceptanceTesting, .server, .hasher:
            return nil
        default:
            return "\(rawValue)IntegrationTests"
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
        let dependencies: [TargetDependency] = switch self {
        case .generator:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.acceptanceTesting.targetName),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeProj"),
            ]
        case .automation:
            [
                .target(name: Module.acceptanceTesting.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.kit.targetName),
                .target(name: Module.support.targetName),
            ]
        case .dependencies:
            [
                .target(name: Module.acceptanceTesting.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.support.targetName),
                .external(name: "XcodeProj"),
            ]
        case .kit:
            [
                .target(name: Module.acceptanceTesting.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.kit.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.server.targetName),
                .target(name: Module.core.targetName),
                .external(name: "XcodeProj"),
            ]
        default:
            []
        }
        return dependencies + sharedDependencies
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
        var dependencies: [TargetDependency] = switch self {
        case .acceptanceTesting:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.kit.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.targetName),
                .external(name: "XcodeProj"),
                .external(name: "XcodeGraph"),
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
            ]
        case .tuistBenchmark:
            [
                .external(name: "SwiftToolsSupport"),
                .external(name: "ArgumentParser"),
            ]
        case .tuistFixtureGenerator:
            [
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
                .external(name: "KeychainAccess"),
                .external(name: "Logging"),
                .external(name: "ZIPFoundation"),
                .external(name: "Difference"),
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
                .external(name: "FileSystem"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "XcodeGraph"),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
                .external(name: "OpenAPIRuntime"),
            ]
        case .core:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.support.targetName),
                .external(name: "XcodeGraph"),
                .external(name: "XcodeProj"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "AnyCodable"),
            ]
        case .generator:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .external(name: "FileSystem"),
                .external(name: "XcodeGraph"),
                .external(name: "SwiftGenKit"),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
                .external(name: "SwiftToolsSupport"),
            ]
        case .scaffold:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .external(name: "FileSystem"),
                .external(name: "XcodeGraph"),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
            ]
        case .loader:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.projectDescription.targetName),
                .external(name: "XcodeGraph"),
                .external(name: "FileSystem"),
                .external(name: "XcodeProj"),
                .external(name: "SwiftToolsSupport"),
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
                .external(name: "FileSystem"),
                .external(name: "XcodeProj"),
                .external(name: "XcbeautifyLib"),
                .external(name: "XcodeGraph"),
            ]
        case .server:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .external(name: "FileSystem"),
                .external(name: "OpenAPIRuntime"),
                .external(name: "OpenAPIURLSession"),
                .external(name: "XcodeGraph"),
            ]
        case .hasher:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .external(name: "XcodeGraph"),
            ]
        case .cache:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.hasher.targetName),
                .external(name: "XcodeGraph"),
            ]
        }
        if self != .projectDescription, self != .projectAutomation {
            dependencies.append(contentsOf: sharedDependencies)
        }
        return dependencies
    }

    public var unitTestDependencies: [TargetDependency] {
        var dependencies: [TargetDependency] = switch self {
        case .tuist, .tuistBenchmark, .acceptanceTesting:
            []
        case .tuistFixtureGenerator:
            [
                .target(name: Module.projectDescription.targetName),
            ]
        case .support:
            [
                .target(name: Module.core.targetName),
                .external(name: "XcodeGraph"),
            ]
        case .projectDescription:
            [
                .target(name: Module.support.testingTargetName!),
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
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.projectAutomation.targetName),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.generator.testingTargetName!),
                .target(name: Module.scaffold.testingTargetName!),
                .target(name: Module.automation.testingTargetName!),
                .target(name: Module.migration.testingTargetName!),
                .target(name: Module.asyncQueue.testingTargetName!),
                .target(name: Module.plugin.targetName),
                .target(name: Module.plugin.testingTargetName!),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
                .external(name: "Difference"),
                .external(name: "XcodeProj"),
                .external(name: "FileSystem"),
                .external(name: "Mockable"),
                .external(name: "XcodeGraph"),
            ]
        case .core:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeGraph"),
            ]
        case .generator:
            [
                .external(name: "PathKit"),
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
                .external(name: "XcodeGraph"),
            ]
        case .scaffold:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
            ]
        case .loader:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .external(name: "Mockable"),
                .external(name: "FileSystem"),
                .external(name: "XcodeGraph"),
            ]
        case .asyncQueue:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .external(name: "Queuer"),
            ]
        case .plugin:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.loader.targetName),
                .target(name: Module.core.targetName),
                .target(name: Module.scaffold.targetName),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.scaffold.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .external(name: "XcodeGraph"),
            ]
        case .analytics:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
            ]
        case .migration:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
            ]
        case .dependencies:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeGraph"),
            ]
        case .automation:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .external(name: "XcodeGraph"),
                .external(name: "FileSystem"),
            ]
        case .server:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .external(name: "Mockable"),
                .external(name: "XcodeGraph"),
                .external(name: "OpenAPIRuntime"),
            ]
        case .hasher:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeGraph"),
            ]
        case .cache:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.hasher.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.support.targetName),
                .external(name: "Mockable"),
                .external(name: "XcodeGraph"),
            ]
        }
        dependencies = dependencies + sharedDependencies + [.target(name: targetName), .external(name: "MockableTest")]
        if let testingTargetName {
            dependencies.append(.target(name: testingTargetName))
        }
        return dependencies
    }

    public var testingDependencies: [TargetDependency] {
        let dependencies: [TargetDependency] = switch self {
        case .tuist, .projectAutomation, .projectDescription, .acceptanceTesting, .server, .hasher, .analytics,
             .migration, .tuistFixtureGenerator, .cache:
            []
        case .asyncQueue:
            [
                .target(name: Module.core.targetName),
            ]
        case .tuistBenchmark:
            [
                .external(name: "ArgumentParser"),
            ]
        case .support:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.core.targetName),
                .external(name: "XcodeGraph"),
                .external(name: "Difference"),
            ]
        case .kit:
            []
        case .core:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
                .external(name: "XcodeGraph"),
            ]
        case .generator:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeProj"),
                .external(name: "XcodeGraph"),
            ]
        case .scaffold:
            [
                .target(name: Module.core.targetName),
                .external(name: "XcodeGraph"),
            ]
        case .loader:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.core.targetName),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeGraph"),
            ]
        case .plugin:
            [
                .target(name: Module.core.targetName),
                .external(name: "XcodeGraph"),
            ]
        case .dependencies:
            [
                .target(name: Module.projectDescription.targetName),
            ]
        case .automation:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeGraph"),
            ]
        }
        return dependencies + sharedDependencies + [.target(name: targetName)]
    }

    public var integrationTestsDependencies: [TargetDependency] {
        var dependencies: [TargetDependency] = switch self {
        case .tuistBenchmark, .tuistFixtureGenerator, .support, .projectAutomation, .projectDescription, .acceptanceTesting,
             .asyncQueue, .plugin, .analytics, .dependencies, .server, .hasher:
            []
        case .cache:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.hasher.targetName),
                .external(name: "XcodeGraph"),
            ]
        case .tuist:
            [
                .target(name: Module.generator.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.support.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.loader.testingTargetName!),
                .external(name: "SwiftToolsSupport"),
                .external(name: "XcodeProj"),
            ]
        case .kit:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.loader.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.automation.targetName),
                .target(name: Module.loader.testingTargetName!),
                .external(name: "XcodeProj"),
                .external(name: "XcodeGraph"),
            ]
        case .core:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
            ]
        case .generator:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeProj"),
                .external(name: "XcodeGraph"),
            ]
        case .scaffold:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
            ]
        case .loader:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
            ]
        case .migration:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
            ]
        case .automation:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
            ]
        }
        dependencies.append(contentsOf: sharedDependencies)
        dependencies.append(.target(name: targetName))
        dependencies.append(.external(name: "MockableTest"))
        if let testingTargetName {
            dependencies.append(contentsOf: [.target(name: testingTargetName)])
        }
        return dependencies
    }

    fileprivate func target(
        name: String,
        product: Product,
        dependencies: [TargetDependency],
        isTestingTarget: Bool
    ) -> Target {
        let rootFolder: String
        switch product {
        case .unitTests:
            rootFolder = "Tests"
        default:
            rootFolder = "Sources"
        }
        var debugSettings: ProjectDescription.SettingsDictionary = ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MOCKING"]
        var releaseSettings: ProjectDescription.SettingsDictionary = [:]
        if isTestingTarget {
            debugSettings["ENABLE_TESTING_SEARCH_PATHS"] = "YES"
            releaseSettings["ENABLE_TESTING_SEARCH_PATHS"] = "YES"
        }

        if let strictConcurrencySetting, product == .framework {
            debugSettings["SWIFT_STRICT_CONCURRENCY"] = .string(strictConcurrencySetting)
            releaseSettings["SWIFT_STRICT_CONCURRENCY"] = .string(strictConcurrencySetting)
        }

        let settings = Settings.settings(
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
        return .target(
            name: name,
            destinations: [.mac],
            product: product,
            bundleId: "io.tuist.\(name)",
            deploymentTargets: .macOS("12.0"),
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
                    "LD_RUNPATH_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                ],
                configurations: [
                    .debug(name: "Debug", settings: [:], xcconfig: nil),
                    .release(name: "Release", settings: [:], xcconfig: nil),
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
