import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistLoader
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct InspectDependenciesCommandServiceTests {
    private let configLoader: MockConfigLoading
    private let generatorFactory: MockGeneratorFactorying
    private let targetScanner: MockTargetImportsScanning
    private let subject: InspectDependenciesCommandService
    private let generator: MockGenerating

    init() throws {
        configLoader = MockConfigLoading()
        generatorFactory = MockGeneratorFactorying()
        targetScanner = MockTargetImportsScanning()
        generator = MockGenerating()
        subject = InspectDependenciesCommandService(
            generatorFactory: generatorFactory,
            configLoader: configLoader,
            graphImportsLinter: GraphImportsLinter(targetScanner: targetScanner)
        )
    }

    // MARK: - Both Checks Tests

    @Test
    func runWithBothChecksFailsOnImplicitIssues() async throws {
        // Given
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

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(implicit: [.init(target: app.productName, dependencies: [framework.productName])])
        ) {
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant])
        }
    }

    @Test
    func runWithBothChecksReportsBothIssuesWhenBothFound() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let featureA = Target.test(name: "FeatureA", product: .framework)
        let sharedCore = Target.test(name: "SharedCore", product: .framework)
        let unusedFramework = Target.test(name: "UnusedFramework", product: .framework)
        let project = Project.test(path: path, targets: [app, featureA, sharedCore, unusedFramework])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                .target(name: app.name, path: path): Set([
                    .target(name: featureA.name, path: path),
                    .target(name: unusedFramework.name, path: path),
                ]),
                .target(name: featureA.name, path: path): Set([
                    .target(name: sharedCore.name, path: path),
                ]),
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["FeatureA", "SharedCore"]))
        given(targetScanner).imports(for: .value(featureA)).willReturn(Set(["SharedCore"]))
        given(targetScanner).imports(for: .value(sharedCore)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(unusedFramework)).willReturn(Set([]))

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(
                implicit: [.init(target: app.productName, dependencies: [sharedCore.productName])],
                redundant: [.init(target: app.productName, dependencies: [unusedFramework.productName])]
            )
        ) {
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant])
        }
    }

    @Test
    func runWithBothChecksFailsOnRedundantIssuesAfterImplicitPasses() async throws {
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

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(redundant: [.init(target: app.productName, dependencies: [extraFramework.productName])])
        ) {
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant])
        }
    }

    @Test
    func runWithBothChecksSucceedsWhenNoIssues() async throws {
        // Given
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

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant])
    }

    @Test
    func graphLoadedOnce() async throws {
        // Given
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

        final class LoadCounter {
            var count = 0
        }
        let loadCounter = LoadCounter()

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willProduce { _, _ in
            loadCounter.count += 1
            return graph
        }
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        // When
        try await subject.run(path: path.pathString, inspectionTypes: [.implicit, .redundant])

        // Then
        #expect(loadCounter.count == 1, "Graph should be loaded exactly once")
    }

    // MARK: - Implicit Check Only Tests

    @Test
    func runImplicitOnlyThrowsErrorWhenThereAreIssues() async throws {
        // Given
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

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(implicit: [.init(target: app.productName, dependencies: [framework.productName])])
        ) {
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit])
        }
    }

    @Test
    func runImplicitOnlyWhenTransitiveLocalDependencyIsImplicitlyImported() async throws {
        // Given
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

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(implicit: [.init(target: "App", dependencies: ["TestTargetDependency"])])
        ) {
            try await subject.run(path: path.pathString, inspectionTypes: [.implicit])
        }
    }

    @Test
    func runImplicitOnlyDoesntThrowErrorsWhenThereAreNoIssues() async throws {
        // Given
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

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.implicit])
    }

    // MARK: - Redundant Check Only Tests

    @Test
    func runRedundantOnlyThrowsErrorWhenThereAreIssues() async throws {
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

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(redundant: [.init(target: app.productName, dependencies: [extraFramework.productName])])
        ) {
            try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
        }
    }

    @Test
    func runRedundantOnlyRespectsIgnoreTags() async throws {
        // Given
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

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    @Test
    func runRedundantOnlyDoesntThrowErrorsWhenThereAreNoIssues() async throws {
        // Given
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

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }
}
