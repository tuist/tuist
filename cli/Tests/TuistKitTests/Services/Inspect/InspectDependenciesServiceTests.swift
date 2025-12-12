import Foundation
import Mockable
import Path
import TuistCore
import TuistLoader
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistKit

final class InspectDependenciesServiceTests: TuistUnitTestCase {
    private var configLoader: MockConfigLoading!
    private var generatorFactory: MockGeneratorFactorying!
    private var targetScanner: MockTargetImportsScanning!
    private var subject: InspectDependenciesService!
    private var generator: MockGenerating!
    private var loadCallCount: Int = 0

    override func setUp() {
        super.setUp()
        configLoader = MockConfigLoading()
        generatorFactory = MockGeneratorFactorying()
        targetScanner = MockTargetImportsScanning()
        generator = MockGenerating()
        loadCallCount = 0
        subject = InspectDependenciesService(
            generatorFactory: generatorFactory,
            configLoader: configLoader,
            graphImportsLinter: GraphImportsLinter(targetScanner: targetScanner)
        )
    }

    override func tearDown() {
        configLoader = nil
        generatorFactory = nil
        targetScanner = nil
        generator = nil
        subject = nil
        super.tearDown()
    }

    // MARK: - Both Checks Tests

    func test_run_withBothChecks_failsOnImplicitIssues() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(path: path, projects: [path: project])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        let expectedIssue = InspectImportsIssue(target: app.productName, dependencies: [framework.productName])
        let expectedError = InspectImportsServiceError.implicitImportsFound([expectedIssue])

        await XCTAssertThrowsSpecific(
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant]),
            expectedError
        )
    }

    func test_run_withBothChecks_failsOnRedundantIssues_afterImplicitPasses() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let extraFramework = Target.test(name: "ExtraFramework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework, extraFramework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                .target(name: app.name, path: path): Set([
                    .target(name: framework.name, path: path),
                    .target(name: extraFramework.name, path: path),
                ]),
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(extraFramework)).willReturn(Set([]))

        let expectedIssue = InspectImportsIssue(target: app.productName, dependencies: [extraFramework.productName])
        let expectedError = InspectImportsServiceError.redundantImportsFound([expectedIssue])

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant]),
            expectedError
        )
    }

    func test_run_withBothChecks_successWhenNoIssues() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [.target(name: app.name, path: path): Set([.target(name: framework.name, path: path)])]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant])
    }

    func test_run_graphLoadedOnce() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [.target(name: app.name, path: path): Set([.target(name: framework.name, path: path)])]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willProduce { _, _ in
            self.loadCallCount += 1
            return graph
        }
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant])

        XCTAssertEqual(loadCallCount, 1, "Graph should be loaded exactly once")
    }

    // MARK: - Implicit Check Only Tests

    func test_run_implicitOnly_throwsAnError_when_thereAreIssues() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(path: path, projects: [path: project])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        let expectedIssue = InspectImportsIssue(target: app.productName, dependencies: [framework.productName])
        let expectedError = InspectImportsServiceError.implicitImportsFound([expectedIssue])

        await XCTAssertThrowsSpecific(try await subject.run(path: path.pathString, inspectionTypes: [.implicit]), expectedError)
    }

    func test_run_implicitOnly_when_transitiveLocalDependencyIsImplicitlyImported() async throws {
        let config = Tuist.test()

        let path = try AbsolutePath(validating: "/project")
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: path, targets: [app])

        let packageTarget = Target.test(name: "PackageTarget", product: .app)
        let packageTargetPath = try AbsolutePath(validating: "/p")
        let packageTargetProject = Project.test(path: packageTargetPath, targets: [packageTarget], type: .external(hash: "hash"))

        let testTarget = Target.test(name: "TestTarget", product: .app)
        let testTargetPath = try AbsolutePath(validating: "/a")
        let testTargetProject = Project.test(path: testTargetPath, targets: [testTarget])

        let testTargetDependency = Target.test(name: "TestTargetDependency", product: .app)
        let testTargetDependencyPath = try AbsolutePath(validating: "/b")
        let testTargetDependencyProject = Project.test(path: testTargetDependencyPath, targets: [testTargetDependency])

        let graph = Graph.test(
            path: path,
            projects: [
                path: project,
                testTargetPath: testTargetProject,
                testTargetDependencyPath: testTargetDependencyProject,
                packageTargetPath: packageTargetProject,
            ],
            dependencies: [
                .target(name: "App", path: path): [
                    .target(name: "PackageTarget", path: packageTargetPath),
                    .target(name: "TestTarget", path: testTargetPath),
                ],
                .target(name: "TestTarget", path: testTargetPath): [
                    .target(name: "TestTargetDependency", path: testTargetDependencyPath),
                ],
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["TestTargetDependency"]))
        given(targetScanner).imports(for: .value(testTarget)).willReturn(Set())
        given(targetScanner).imports(for: .value(testTargetDependency)).willReturn(Set())

        await XCTAssertThrowsSpecific(
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit]),
            InspectImportsServiceError.implicitImportsFound(
                [
                    InspectImportsIssue(
                        target: "App",
                        dependencies: ["TestTargetDependency"]
                    ),
                ]
            )
        )
    }

    func test_run_implicitOnly_doesntThrowAnyErrors_when_thereAreNoIssues() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [.target(name: app.name, path: path): Set([.target(name: framework.name, path: path)])]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        try await subject.run(path: path.pathString, inspectionTypes: [.implicit])
    }

    // MARK: - Redundant Check Only Tests

    func test_run_redundantOnly_throwsAnError_when_thereAreIssues() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let extraFramework = Target.test(name: "ExtraFramework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework, extraFramework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                .target(name: app.name, path: path): Set([
                    .target(name: framework.name, path: path),
                    .target(name: extraFramework.name, path: path),
                ]),
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(extraFramework)).willReturn(Set([]))

        let expectedIssue = InspectImportsIssue(target: app.productName, dependencies: [extraFramework.productName])
        let expectedError = InspectImportsServiceError.redundantImportsFound([expectedIssue])

        await XCTAssertThrowsSpecific(
            try await subject.run(path: path.pathString, inspectionTypes: [.redundant]),
            expectedError
        )
    }

    func test_run_redundantOnly_respectsIgnoreTags() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test(
            inspectOptions: .init(
                redundantDependencies: .init(ignoreTagsMatching: ["IgnoreTag"])
            )
        )
        let app = Target.test(name: "App", product: .app, metadata: .metadata(tags: ["IgnoreTag"]))
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [.target(name: app.name, path: path): Set([.target(name: framework.name, path: path)])]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    func test_run_redundantOnly_doesntThrowAnyErrors_when_thereAreNoIssues() async throws {
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [.target(name: app.name, path: path): Set([.target(name: framework.name, path: path)])]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }
}
