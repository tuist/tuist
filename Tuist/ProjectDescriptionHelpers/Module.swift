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
            targets.append(.target(
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
                .target(
                    name: unitTestsTargetName,
                    product: .unitTests,
                    dependencies: unitTestDependencies
                )
            )
        }

        if let integrationTestsTargetName {
            targets.append(
                .target(
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
                .target(
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
            .target(
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
                .target(name: "TuistAcceptanceTesting"),
                .target(name: "TuistSupportTesting"),
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
                .target(name: "TuistKit"),
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCore"),
                .external(name: "XcodeProj"),
                .sdk(name: "XCTest", type: .framework, status: .optional),
            ]
        case .tuist:
            [
                .target(name: "TuistKit"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
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
                .target(name: "ProjectDescription"),
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
                .target(name: "TuistSupport"),
                .target(name: "TuistGenerator"),
                .target(name: "TuistAutomation"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoader"),
                .target(name: "TuistScaffold"),
                .target(name: "TuistDependencies"),
                .target(name: "TuistMigration"),
                .target(name: "TuistAsyncQueue"),
                .target(name: "TuistAnalytics"),
                .target(name: "TuistPlugin"),
                .target(name: "TuistGraph"),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
            ]
        case .graph:
            [
                .target(name: "TuistSupport"),
                .external(name: "AnyCodable"),
            ]
        case .core:
            [
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .external(name: "XcodeProj"),
            ]
        case .generator:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "SwiftGenKit"),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
            ]
        case .scaffold:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "PathKit"),
                .external(name: "StencilSwiftKit"),
            ]
        case .loader:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .target(name: "ProjectDescription"),
                .external(name: "XcodeProj"),
            ]
        case .asyncQueue:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "Queuer"),
                .external(name: "XcodeProj"),
            ]
        case .plugin:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistLoader"),
                .target(name: "TuistSupport"),
                .target(name: "TuistScaffold"),
            ]
        case .analytics:
            [
                .target(name: "TuistAsyncQueue"),
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistLoader"),
                .target(name: "TuistSupport"),
                .external(name: "AnyCodable"),
            ]
        case .migration:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
                .external(name: "PathKit"),
                .external(name: "XcodeProj"),
            ]
        case .dependencies:
            [
                .target(name: "ProjectDescription"),
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
            ]
        case .automation:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupport"),
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
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistSupport"),
            ]
        case .projectAutomation:
            []
        case .kit:
            [
                .target(name: "TuistAutomation"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistGeneratorTesting"),
                .target(name: "TuistScaffoldTesting"),
                .target(name: "TuistAutomationTesting"),
                .target(name: "TuistMigrationTesting"),
                .target(name: "TuistAsyncQueueTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistPlugin"),
                .target(name: "TuistPluginTesting"),
                .external(name: "ArgumentParser"),
                .external(name: "GraphViz"),
                .external(name: "AnyCodable"),
            ]
        case .graph:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
                .external(name: "XcodeProj"),
            ]
        case .core:
            [
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        case .generator:
            [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "XcodeProj"),
                .external(name: "GraphViz"),
            ]
        case .scaffold:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        case .loader:
            [
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
            ]
        case .asyncQueue:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "Queuer"),
            ]
        case .plugin:
            [
                .target(name: "ProjectDescription"),
                .target(name: "TuistLoader"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistScaffoldTesting"),
                .target(name: "TuistCoreTesting"),
            ]
        case .analytics:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistCoreTesting"),
            ]
        case .migration:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        case .dependencies:
            [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistSupportTesting"),
            ]
        case .automation:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
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
                .target(name: "TuistCore"),
                .target(name: "TuistGraph"),
            ]
        case .kit:
            []
        case .graph:
            [
                .target(name: "TuistSupport"),
                .target(name: "TuistSupportTesting"),
                .external(name: "XcodeProj"),
            ]
        case .core:
            [
                .target(name: "TuistSupport"),
                .target(name: "TuistGraph"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        case .generator:
            [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "XcodeProj"),
            ]
        case .scaffold:
            [
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistGraph"),
            ]
        case .loader:
            [
                .target(name: "TuistCore"),
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistGraph"),
            ]
        case .asyncQueue:
            [
                .target(name: "TuistGraphTesting"),
            ]
        case .plugin:
            [
                .target(name: "TuistGraph"),
            ]
        case .analytics:
            []
        case .migration:
            [
                .target(name: "TuistGraphTesting"),
            ]
        case .dependencies:
            [
                .target(name: "TuistGraphTesting"),
                .target(name: "ProjectDescription"),
            ]
        case .automation:
            [
                .target(name: "TuistCore"),
                .target(name: "TuistCoreTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
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
                .target(name: "TuistGenerator"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistSupport"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistLoaderTesting"),
                .external(name: "SwiftToolsSupport"),
                .external(name: "XcodeProj"),
            ]
        case .kit:
            [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "ProjectDescription"),
                .target(name: "ProjectAutomation"),
                .target(name: "TuistLoaderTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "XcodeProj"),
            ]
        case .graph:
            []
        case .core:
            [
                .target(name: "TuistSupportTesting"),
            ]
        case .generator:
            [
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
                .external(name: "XcodeProj"),
            ]
        case .scaffold:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        case .loader:
            [
                .target(name: "TuistGraphTesting"),
                .target(name: "TuistSupportTesting"),
                .target(name: "ProjectDescription"),
            ]
        case .asyncQueue:
            []
        case .plugin:
            []
        case .analytics:
            []
        case .migration:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistCoreTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        case .dependencies:
            []
        case .automation:
            [
                .target(name: "TuistSupportTesting"),
                .target(name: "TuistGraphTesting"),
            ]
        }
        dependencies.append(contentsOf: sharedDependencies)
        dependencies.append(.target(name: targetName))
        if let testingTargetName {
            dependencies.append(contentsOf: [.target(name: testingTargetName)])
        }
        return dependencies
    }

    public var settings: Settings {
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
