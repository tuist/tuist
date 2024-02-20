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
    case graph = "TuistGraph"
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
                dependencies: acceptanceTestDependencies
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
                    dependencies: unitTestDependencies
                )
            )
        }

        if let integrationTestsTargetName {
            targets.append(
                target(
                    name: integrationTestsTargetName,
                    product: .unitTests,
                    dependencies: integrationTestsDependencies
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
                    dependencies: testingDependencies
                )
            )
        }

        return targets + testTargets
    }

    public var sourceTargets: [Target] {
        let isStaticProduct = product == .staticLibrary || product == .staticFramework

        return [
            target(
                name: targetName,
                product: product,
                dependencies: dependencies + (isStaticProduct ? [
                    .external(name: "Mockable"),
                ] : [])
            ),
        ]
    }

    fileprivate var sharedDependencies: [TargetDependency] {
        return [
            .external(name: "SwiftToolsSupport"),
            .external(name: "SystemPackage"),
        ]
    }

    public var acceptanceTestsTargetName: String? {
        switch self {
        case .tuist, .automation, .dependencies, .generator:
            return "\(rawValue)AcceptanceTests"
        default:
            return nil
        }
    }

    public var testingTargetName: String? {
        switch self {
        case .tuist, .tuistBenchmark, .tuistFixtureGenerator, .kit, .projectAutomation, .projectDescription, .analytics,
             .dependencies, .acceptanceTesting:
            return nil
        default:
            return "\(rawValue)Testing"
        }
    }

    public var unitTestsTargetName: String? {
        switch self {
        case .automation, .analytics, .tuist, .tuistBenchmark, .tuistFixtureGenerator, .projectAutomation, .projectDescription,
             .acceptanceTesting:
            return nil
        default:
            return "\(rawValue)Tests"
        }
    }

    public var integrationTestsTargetName: String? {
        switch self {
        case .tuist, .tuistBenchmark, .tuistFixtureGenerator, .projectAutomation, .projectDescription, .graph, .asyncQueue,
             .plugin, .analytics, .dependencies, .acceptanceTesting:
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
        case .tuist, .automation, .dependencies, .generator:
            [
                .target(name: Module.acceptanceTesting.targetName),
                .target(name: Module.support.testingTargetName!),
            ]
        default:
            []
        }
        return dependencies + sharedDependencies
    }

    public var dependencies: [TargetDependency] {
        var dependencies: [TargetDependency] = switch self {
        case .acceptanceTesting:
            [
                .target(name: Module.kit.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.targetName),
                .external(name: "XcodeProj"),
                .sdk(name: "XCTest", type: .framework, status: .optional),
            ]
        case .tuist:
            [
                .target(name: Module.kit.targetName),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.automation.targetName),
                .external(name: "GraphViz"),
                .external(name: "ArgumentParser"),
            ]
        case .tuistBenchmark:
            [
                .external(name: "ArgumentParser"),
            ]
        case .tuistFixtureGenerator:
            [
                .external(name: "ArgumentParser"),
            ]
        case .projectAutomation, .projectDescription:
            []
        case .support:
            [
                .target(name: Module.projectDescription.targetName),
                .external(name: "AnyCodable"),
                .external(name: "XcodeProj"),
                .external(name: "KeychainAccess"),
                .external(name: "CombineExt"),
                .external(name: "Logging"),
                .external(name: "ZIPFoundation"),
                .external(name: "Difference"),
            ]
        case .kit:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.generator.targetName),
                .target(name: Module.automation.targetName),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.automation.targetName),
                .target(name: Module.loader.targetName),
                .target(name: Module.scaffold.targetName),
                .target(name: Module.dependencies.targetName),
                .target(name: Module.migration.targetName),
                .target(name: Module.asyncQueue.targetName),
                .target(name: Module.analytics.targetName),
                .target(name: Module.plugin.targetName),
                .target(name: Module.graph.targetName),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
            ]
        case .graph:
            [
                .target(name: Module.support.targetName),
                .external(name: "AnyCodable"),
            ]
        case .core:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.graph.targetName),
                .external(name: "XcodeProj"),
            ]
        case .generator:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.targetName),
                .external(name: "SwiftGenKit"),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
            ]
        case .scaffold:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.targetName),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
            ]
        case .loader:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.projectDescription.targetName),
                .external(name: "XcodeProj"),
            ]
        case .asyncQueue:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.targetName),
                .external(name: "Queuer"),
                .external(name: "XcodeProj"),
            ]
        case .plugin:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.loader.targetName),
                .target(name: Module.support.targetName),
                .target(name: Module.scaffold.targetName),
            ]
        case .analytics:
            [
                .target(name: Module.asyncQueue.targetName),
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.loader.targetName),
                .target(name: Module.support.targetName),
                .external(name: "AnyCodable"),
            ]
        case .migration:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.targetName),
                .external(name: "PathKit"),
                .external(name: "XcodeProj"),
            ]
        case .dependencies:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.targetName),
            ]
        case .automation:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.targetName),
                .external(name: "XcodeProj"),
                .external(name: "XcbeautifyLib"),
            ]
        }
        if self != .projectDescription, self != .projectAutomation {
            dependencies.append(contentsOf: sharedDependencies)
        }
        return dependencies
    }

    public var unitTestDependencies: [TargetDependency] {
        var dependencies: [TargetDependency] = switch self {
        case .tuist, .tuistBenchmark, .tuistFixtureGenerator, .support, .acceptanceTesting:
            []
        case .projectDescription:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.support.targetName),
            ]
        case .projectAutomation:
            []
        case .kit:
            [
                .target(name: Module.automation.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.automation.targetName),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.generator.testingTargetName!),
                .target(name: Module.scaffold.testingTargetName!),
                .target(name: Module.automation.testingTargetName!),
                .target(name: Module.migration.testingTargetName!),
                .target(name: Module.asyncQueue.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.plugin.targetName),
                .target(name: Module.plugin.testingTargetName!),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
            ]
        case .graph:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeProj"),
            ]
        case .core:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        case .generator:
            [
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
            ]
        case .scaffold:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        case .loader:
            [
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
            ]
        case .asyncQueue:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .external(name: "Queuer"),
            ]
        case .plugin:
            [
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.loader.targetName),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.scaffold.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
            ]
        case .analytics:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
            ]
        case .migration:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        case .dependencies:
            [
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
            ]
        case .automation:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
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
        case .tuist, .projectAutomation, .projectDescription, .acceptanceTesting:
            []
        case .tuistBenchmark:
            [
                .external(name: "ArgumentParser"),
            ]
        case .tuistFixtureGenerator:
            []
        case .support:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.graph.targetName),
            ]
        case .kit:
            []
        case .graph:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.support.testingTargetName!),
                .external(name: "XcodeProj"),
            ]
        case .core:
            [
                .target(name: Module.support.targetName),
                .target(name: Module.graph.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        case .generator:
            [
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .external(name: "XcodeProj"),
            ]
        case .scaffold:
            [
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.graph.targetName),
            ]
        case .loader:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.graph.targetName),
            ]
        case .asyncQueue:
            [
                .target(name: Module.graph.testingTargetName!),
            ]
        case .plugin:
            [
                .target(name: Module.graph.targetName),
            ]
        case .analytics:
            []
        case .migration:
            [
                .target(name: Module.graph.testingTargetName!),
            ]
        case .dependencies:
            [
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
            ]
        case .automation:
            [
                .target(name: Module.core.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        }
        return dependencies + sharedDependencies + [
            .target(name: targetName),
            .sdk(name: "XCTest", type: .framework, status: .optional),
        ]
    }

    public var integrationTestsDependencies: [TargetDependency] {
        var dependencies: [TargetDependency] = switch self {
        case .tuistBenchmark, .tuistFixtureGenerator, .support, .projectAutomation, .projectDescription, .acceptanceTesting:
            []
        case .tuist:
            [
                .target(name: Module.generator.targetName),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.support.targetName),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.loader.testingTargetName!),
                .external(name: "SwiftToolsSupport"),
                .external(name: "XcodeProj"),
            ]
        case .kit:
            [
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
                .target(name: Module.automation.targetName),
                .target(name: Module.loader.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .external(name: "XcodeProj"),
            ]
        case .graph:
            []
        case .core:
            [
                .target(name: Module.support.testingTargetName!),
            ]
        case .generator:
            [
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
                .external(name: "XcodeProj"),
            ]
        case .scaffold:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        case .loader:
            [
                .target(name: Module.graph.testingTargetName!),
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.projectDescription.targetName),
            ]
        case .asyncQueue:
            []
        case .plugin:
            []
        case .analytics:
            []
        case .migration:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.core.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        case .dependencies:
            []
        case .automation:
            [
                .target(name: Module.support.testingTargetName!),
                .target(name: Module.graph.testingTargetName!),
            ]
        }
        dependencies.append(contentsOf: sharedDependencies)
        dependencies.append(.target(name: targetName))
        if let testingTargetName {
            dependencies.append(contentsOf: [.target(name: testingTargetName)])
        }
        return dependencies
    }

    fileprivate func target(
        name: String,
        product: Product,
        dependencies: [TargetDependency],
        settings: Settings = .settings(
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
    ) -> Target {
        let rootFolder: String
        switch product {
        case .unitTests:
            rootFolder = "Tests"
        default:
            rootFolder = "Sources"
        }
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
