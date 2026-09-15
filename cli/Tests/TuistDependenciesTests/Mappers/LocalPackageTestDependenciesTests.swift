import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph

@testable import TuistDependencies

struct LocalPackageTestDependenciesTests {
    @Test(arguments: [false, true])
    func preservesTestOnlyDependenciesAcrossPackages(crossPackageRuntime: Bool) async throws {
        let appPath = try AbsolutePath(validating: "/App")
        let runtimePath = try AbsolutePath(validating: "/RuntimePackage")
        let supportPath = try AbsolutePath(validating: "/SupportPackage")
        let corePath = try AbsolutePath(validating: "/CorePackage")
        let app = Target.test(name: "App", destinations: [.iPhone], product: .app)
        let runtime = Target.test(name: "Runtime", destinations: [.iPhone, .mac], product: .staticFramework)
        let tests = Target.test(
            name: "RuntimeTests",
            destinations: [.iPhone, .mac],
            product: .unitTests,
            dependencies: [
                crossPackageRuntime
                    ? .project(target: "Runtime", path: runtimePath)
                    : .target(name: "Runtime"),
                .project(target: "Support", path: supportPath),
            ],
            metadata: .test(tags: [TargetTags.localSwiftPackageTest])
        )
        let support = Target.test(name: "Support", destinations: [.iPhone, .mac], product: .staticFramework)
        let core = Target.test(name: "Core", destinations: [.iPhone, .mac], product: .staticFramework)
        let utilities = Target.test(name: "Utilities", destinations: [.iPhone, .mac], product: .staticFramework)
        let unused = Target.test(name: "Unused", destinations: [.iPhone, .mac], product: .staticFramework)
        let macOnly = Target.test(name: "MacOnly", destinations: [.mac], product: .staticFramework)
        let macro = Target.test(name: "SupportMacro", destinations: [.mac], product: .macro)
        let macroHelper = Target.test(name: "MacroHelper", destinations: [.mac], product: .staticFramework)
        let remoteTests = Target.test(name: "RemoteTests", destinations: [.iPhone, .mac], product: .unitTests)
        let testPath = crossPackageRuntime ? supportPath : runtimePath
        let graph = Graph.test(
            projects: [
                appPath: .test(path: appPath, targets: [app]),
                runtimePath: .test(
                    path: runtimePath,
                    targets: crossPackageRuntime ? [runtime] : [runtime, tests],
                    type: .external(hash: nil)
                ),
                supportPath: .test(
                    path: supportPath,
                    targets: [support, unused, remoteTests] + (crossPackageRuntime ? [tests] : []),
                    type: .external(hash: nil)
                ),
                corePath: .test(
                    path: corePath,
                    targets: [core, utilities, macOnly, macro, macroHelper],
                    type: .external(hash: nil)
                ),
            ],
            dependencies: [
                .target(name: "App", path: appPath): [.target(name: "Runtime", path: runtimePath)],
                .target(name: "RuntimeTests", path: testPath): [
                    .target(name: "Runtime", path: runtimePath),
                    .target(name: "Support", path: supportPath),
                ],
                .target(name: "Support", path: supportPath): [
                    .target(name: "Core", path: corePath),
                    .target(name: "MacOnly", path: corePath),
                    .target(name: "SupportMacro", path: corePath),
                ],
                .target(name: "SupportMacro", path: corePath): [.target(name: "MacroHelper", path: corePath)],
                .target(name: "Core", path: corePath): [.target(name: "Utilities", path: corePath)],
            ],
            dependencyConditions: [
                GraphEdge(from: .target(name: "Support", path: supportPath), to: .target(name: "MacOnly", path: corePath)):
                    try #require(PlatformCondition.when([.macos])),
            ]
        )

        let (narrowed, _, _) = try await ExternalProjectsPlatformNarrowerGraphMapper().map(
            graph: graph, environment: MapperEnvironment()
        )
        let (pruned, _, _) = try await PruneOrphanExternalTargetsGraphMapper().map(
            graph: narrowed, environment: MapperEnvironment()
        )

        for (path, name) in [
            (testPath, "RuntimeTests"),
            (supportPath, "Support"),
            (corePath, "Core"),
            (corePath, "Utilities"),
        ] {
            let target = try #require(pruned.projects[path]?.targets[name])
            #expect(!target.metadata.tags.contains("tuist:prunable"))
            #expect(target.destinations == [.iPhone])
        }
        for name in ["SupportMacro", "MacroHelper"] {
            let target = try #require(pruned.projects[corePath]?.targets[name])
            #expect(!target.metadata.tags.contains("tuist:prunable"))
            #expect(target.destinations == [.mac])
        }
        let macOnlyTarget = try #require(pruned.projects[corePath]?.targets["MacOnly"])
        #expect(macOnlyTarget.metadata.tags.contains("tuist:prunable"))
        for name in ["Unused", "RemoteTests"] {
            let target = try #require(pruned.projects[supportPath]?.targets[name])
            #expect(target.metadata.tags.contains("tuist:prunable"))
        }
    }

    @Test(arguments: [false, true])
    func ignoresTestsWithoutProductionReachableDependencies(supportDependsOnRuntime: Bool) async throws {
        let appPath = try AbsolutePath(validating: "/App")
        let packagePath = try AbsolutePath(validating: "/Package")
        let runtime = Target.test(
            name: "Runtime", destinations: [.iPhone, .mac, .appleTv, .appleWatch], product: .staticFramework,
            deploymentTargets: .init(iOS: "15.0", macOS: "12.0", watchOS: "8.0", tvOS: "15.0")
        )
        let support = Target.test(name: "Support", destinations: runtime.destinations, product: .staticFramework)
        let tests = Target.test(
            name: "SupportTests", destinations: runtime.destinations, product: .unitTests,
            dependencies: [.target(name: "Support")],
            metadata: .test(tags: [TargetTags.localSwiftPackageTest])
        )
        let graph = Graph.test(
            projects: [
                appPath: .test(path: appPath, targets: [.test(name: "App", destinations: [.iPhone], product: .app)]),
                packagePath: .test(path: packagePath, targets: [runtime, support, tests], type: .external(hash: nil)),
            ],
            dependencies: [
                .target(name: "App", path: appPath): [.target(name: "Runtime", path: packagePath)],
                .target(name: "SupportTests", path: packagePath): [.target(name: "Support", path: packagePath)],
                .target(name: "Support", path: packagePath): supportDependsOnRuntime
                    ? [.target(name: "Runtime", path: packagePath)] : [],
            ]
        )
        let (narrowed, _, _) = try await ExternalProjectsPlatformNarrowerGraphMapper().map(
            graph: graph, environment: MapperEnvironment()
        )
        let mappedRuntime = try #require(narrowed.projects[packagePath]?.targets["Runtime"])
        #expect(mappedRuntime.destinations == [.iPhone])
        #expect(mappedRuntime.deploymentTargets == .iOS("15.0"))

        let (pruned, _, _) = try await PruneOrphanExternalTargetsGraphMapper().map(
            graph: narrowed, environment: MapperEnvironment()
        )
        for name in ["Support", "SupportTests"] {
            let target = try #require(pruned.projects[packagePath]?.targets[name])
            #expect(target.metadata.tags.contains("tuist:prunable"))
        }
    }
}
