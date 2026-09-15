import Path
import Testing
import TuistCore
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
}
