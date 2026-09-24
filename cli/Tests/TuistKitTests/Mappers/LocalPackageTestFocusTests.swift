import Path
import Testing
import TuistCore
import TuistDependencies
import TuistGenerator
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct LocalPackageTestFocusTests {
    @Test(arguments: [false, true])
    func preservesTestDependencyClosureUnlessExplicitlyFocused(explicitFocus: Bool) throws {
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
            dependencies: [.target(name: "Runtime"), .project(target: "Support", path: supportPath)],
            metadata: .test(tags: [TargetTags.localSwiftPackageTest])
        )
        let support = Target.test(name: "Support", destinations: [.iPhone, .mac], product: .staticFramework)
        let core = Target.test(name: "Core", destinations: [.iPhone, .mac], product: .staticFramework)
        let utilities = Target.test(name: "Utilities", destinations: [.iPhone, .mac], product: .staticFramework)
        let unused = Target.test(name: "Unused", destinations: [.iPhone, .mac], product: .staticFramework)
        let remoteTests = Target.test(name: "RemoteTests", destinations: [.iPhone, .mac], product: .unitTests)
        let graph = Graph.test(
            projects: [
                appPath: .test(path: appPath, targets: [app]),
                runtimePath: .test(path: runtimePath, targets: [runtime, tests], type: .external(hash: nil)),
                supportPath: .test(path: supportPath, targets: [support, unused, remoteTests], type: .external(hash: nil)),
                corePath: .test(path: corePath, targets: [core, utilities], type: .external(hash: nil)),
            ],
            dependencies: [
                .target(name: "App", path: appPath): [.target(name: "Runtime", path: runtimePath)],
                .target(name: "RuntimeTests", path: runtimePath): [
                    .target(name: "Runtime", path: runtimePath),
                    .target(name: "Support", path: supportPath),
                ],
                .target(name: "Support", path: supportPath): [.target(name: "Core", path: corePath)],
                .target(name: "Core", path: corePath): [.target(name: "Utilities", path: corePath)],
            ]
        )

        let mapper = FocusTargetsGraphMappers(includedTargets: explicitFocus ? [.named("App")] : [])
        let (mapped, _, _) = try mapper.map(graph: graph, environment: MapperEnvironment())
        for (path, name) in [
            (runtimePath, "RuntimeTests"),
            (supportPath, "Support"),
            (corePath, "Core"),
            (corePath, "Utilities"),
        ] {
            let target = try #require(mapped.projects[path]?.targets[name])
            #expect(target.metadata.tags.contains("tuist:prunable") == explicitFocus)
        }
        for name in ["Unused", "RemoteTests"] {
            let target = try #require(mapped.projects[supportPath]?.targets[name])
            #expect(target.metadata.tags.contains("tuist:prunable"))
        }
    }

    @Test func selectedSchemeKeepsInferredPlatformsAfterRemovingProductionConsumers() async throws {
        let appPath = try AbsolutePath(validating: "/App")
        let packagePath = try AbsolutePath(validating: "/Package")
        let runtime = Target.test(name: "Runtime", destinations: [.iPhone, .mac], product: .staticFramework)
        let support = Target.test(name: "Support", destinations: [.iPhone, .mac], product: .staticFramework)
        let tests = ["SelectedTests", "OtherTests"].map { name in
            Target.test(
                name: name, destinations: [.iPhone, .mac], product: .unitTests,
                dependencies: [.target(name: "Runtime"), .target(name: "Support")],
                metadata: .test(tags: [TargetTags.localSwiftPackageTest])
            )
        }
        let graph = Graph.test(
            projects: [
                appPath: .test(
                    path: appPath,
                    targets: [.test(name: "App", destinations: [.iPhone], product: .app)],
                    schemes: [.test(name: "Selected", testAction: .test(targets: [
                        .test(target: TargetReference(projectPath: packagePath, name: "SelectedTests")),
                    ]))]
                ),
                packagePath: .test(path: packagePath, targets: [runtime, support] + tests, type: .external(hash: nil)),
            ],
            dependencies: [
                .target(name: "App", path: appPath): [.target(name: "Runtime", path: packagePath)],
                .target(name: "SelectedTests", path: packagePath): [
                    .target(name: "Runtime", path: packagePath), .target(name: "Support", path: packagePath),
                ],
                .target(name: "OtherTests", path: packagePath): [
                    .target(name: "Runtime", path: packagePath), .target(name: "Support", path: packagePath),
                ],
            ]
        )
        let (focused, _, environment) = try FocusTargetsGraphMappers(
            schemeName: "Selected", includedTargets: [], includedProducts: [.unitTests, .uiTests]
        ).map(graph: graph, environment: MapperEnvironment())
        let (shaken, _, _) = try await TreeShakePrunedTargetsGraphMapper().map(graph: focused, environment: environment)
        #expect(shaken.projects[appPath]?.targets["App"] == nil)
        #expect(shaken.projects[packagePath]?.targets["OtherTests"] == nil)
        let (narrowed, _, _) = try await ExternalProjectsPlatformNarrowerGraphMapper().map(
            graph: shaken,
            environment: environment
        )
        let (pruned, _, _) = try await PruneOrphanExternalTargetsGraphMapper().map(graph: narrowed, environment: environment)
        for name in ["SelectedTests", "Runtime", "Support"] {
            let target = try #require(pruned.projects[packagePath]?.targets[name])
            #expect(target.destinations == [.iPhone])
            #expect(!target.metadata.tags.contains("tuist:prunable"))
        }
    }
}
