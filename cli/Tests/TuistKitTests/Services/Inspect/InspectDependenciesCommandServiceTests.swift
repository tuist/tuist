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
            throws: InspectImportsServiceError.issuesFound(implicit: [.init(
                target: app.productName,
                dependencies: [framework.productName]
            )])
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
            throws: InspectImportsServiceError.issuesFound(redundant: [.init(
                target: app.productName,
                dependencies: [extraFramework.productName]
            )])
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
            throws: InspectImportsServiceError.issuesFound(implicit: [.init(
                target: app.productName,
                dependencies: [framework.productName]
            )])
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
        given(targetScanner).imports(for: .value(testTarget)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(testTargetDependency)).willReturn(Set([]))

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(implicit: [.init(
                target: "App",
                dependencies: ["TestTargetDependency"]
            )])
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
            throws: InspectImportsServiceError.issuesFound(redundant: [.init(
                target: app.productName,
                dependencies: [extraFramework.productName]
            )])
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

    // MARK: - Redundant Check: Special Product Types

    @Test
    func runRedundantOnlyDoesntFlagExternalPackageTargets() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: path, targets: [app])
        let testTarget = Target.test(name: "PackageTarget", product: .app)
        let externalTargetDependency = Target.test(name: "PackageTargetDependency", product: .app)
        let externalProject = Project.test(
            path: path,
            targets: [testTarget, externalTargetDependency],
            type: .external(hash: "hash")
        )
        let graph = Graph.test(
            path: path,
            projects: [path: project, "/a": externalProject],
            dependencies: [
                GraphDependency.target(name: "App", path: path): Set([
                    GraphDependency.target(name: "PackageTarget", path: "/a"),
                ]),
                GraphDependency
                    .target(
                        name: "PackageTarget",
                        path: "/a"
                    ): Set([GraphDependency.target(name: "PackageTargetDependency", path: "/a")]),
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    @Test
    func runRedundantOnlyDoesntFlagBundleDependencies() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let bundleFramework = Target.test(
            name: "Core_Framework",
            product: .bundle,
            bundleId: "framework.generated.resources"
        )

        let framework = Target.test(
            name: "Framework",
            product: .framework,
            dependencies: [TargetDependency.target(name: "Core_Framework")]
        )
        let project = Project.test(path: path, targets: [bundleFramework, framework])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: framework.name, path: project.path): [
                .target(name: bundleFramework.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(bundleFramework)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    @Test
    func runRedundantOnlyDoesntFlagTestTargetDependencies() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let unitTests = Target.test(
            name: "AppTests",
            product: .unitTests,
            dependencies: [TargetDependency.target(name: "App")]
        )
        let uiTests = Target.test(
            name: "AppUITests",
            product: .uiTests,
            dependencies: [TargetDependency.target(name: "App")]
        )

        let project = Project.test(path: path, targets: [app, unitTests, uiTests])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: unitTests.name, path: project.path): [
                .target(name: app.name, path: project.path),
            ],
            .target(name: uiTests.name, path: project.path): [
                .target(name: app.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(unitTests)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(uiTests)).willReturn(Set([]))

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    @Test
    func runRedundantOnlyDoesntFlagAppExtensions() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let stickerPackExtension = Target.test(name: "StickerPackExtension", product: .stickerPackExtension)
        let appIntentExtension = Target.test(name: "AppIntentExtension", product: .extensionKitExtension)
        let messageExtension = Target.test(name: "MessageExtension", product: .messagesExtension)

        let app = Target.test(
            name: "App",
            product: .app,
            dependencies: [
                TargetDependency.target(name: "AppExtension"),
                TargetDependency.target(name: "StickerPackExtension"),
                TargetDependency.target(name: "AppIntentExtension"),
                TargetDependency.target(name: "MessageExtension"),
            ]
        )
        let project = Project.test(
            path: path,
            targets: [appExtension, stickerPackExtension, appIntentExtension, messageExtension, app]
        )
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: appExtension.name, path: project.path),
                .target(name: stickerPackExtension.name, path: project.path),
                .target(name: appIntentExtension.name, path: project.path),
                .target(name: messageExtension.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(appExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(stickerPackExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(appIntentExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(messageExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    @Test
    func runRedundantOnlyDoesntFlagWatchAppDependencies() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let watch2Extension = Target.test(name: "Watch2Extension", product: .watch2Extension)
        let watch2App = Target.test(
            name: "Watch2App",
            product: .watch2App,
            dependencies: [TargetDependency.target(name: "Watch2Extension")]
        )
        let app = Target.test(
            name: "App",
            product: .app,
            dependencies: [TargetDependency.target(name: "Watch2App")]
        )

        let project = Project.test(path: path, targets: [watch2Extension, watch2App, app])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: watch2App.name, path: project.path),
            ],
            .target(name: watch2App.name, path: project.path): [
                .target(name: watch2Extension.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(watch2Extension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(watch2App)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    @Test
    func runRedundantOnlyDoesntFlagMacroDependencies() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let macro = Target.test(name: "MyMacro", product: .macro)
        let framework = Target.test(
            name: "Framework",
            product: .framework,
            dependencies: [TargetDependency.target(name: "MyMacro")]
        )
        let project = Project.test(path: path, targets: [framework, macro])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: framework.name, path: project.path): [
                .target(name: macro.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(macro)).willReturn(Set([]))

        // When / Then
        try await subject.run(path: path.pathString, inspectionTypes: [.redundant])
    }

    // MARK: - Redundant Check: Cross-Project Dependencies

    @Test
    func runRedundantOnlyThrowsErrorForCrossProjectRedundantDependency() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/project")
        let libraryPath = try AbsolutePath(validating: "/library")
        let config = Tuist.test()

        let uiComponent = Target.test(name: "UIComponent", product: .framework)
        let libraryProject = Project.test(path: libraryPath, targets: [uiComponent])

        let feature = Target.test(
            name: "Feature",
            product: .framework,
            dependencies: [TargetDependency.project(target: "UIComponent", path: libraryPath)]
        )
        let mainProject = Project.test(path: projectPath, targets: [feature])

        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: mainProject, libraryPath: libraryProject],
            dependencies: [
                .target(name: feature.name, path: projectPath): [
                    .target(name: uiComponent.name, path: libraryPath),
                ],
            ]
        )

        given(configLoader).loadConfig(path: .value(projectPath)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(projectPath), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(feature)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(uiComponent)).willReturn(Set([]))

        // When / Then
        await #expect(
            throws: InspectImportsServiceError.issuesFound(
                redundant: [.init(target: feature.productName, dependencies: [uiComponent.productName])]
            )
        ) {
            try await subject.run(path: projectPath.pathString, inspectionTypes: [.redundant])
        }
    }

    @Test
    func runRedundantOnlyDoesntFlagCrossProjectDependenciesWhenImported() async throws {
        // Given
        let projectPath = try AbsolutePath(validating: "/project")
        let libraryPath = try AbsolutePath(validating: "/library")
        let config = Tuist.test()

        let uiComponent = Target.test(name: "UIComponent", product: .framework)
        let libraryProject = Project.test(path: libraryPath, targets: [uiComponent])

        let feature = Target.test(
            name: "Feature",
            product: .framework,
            dependencies: [TargetDependency.project(target: "UIComponent", path: libraryPath)]
        )
        let mainProject = Project.test(path: projectPath, targets: [feature])

        let graph = Graph.test(
            path: projectPath,
            projects: [projectPath: mainProject, libraryPath: libraryProject],
            dependencies: [
                .target(name: feature.name, path: projectPath): [
                    .target(name: uiComponent.name, path: libraryPath),
                ],
            ]
        )

        given(configLoader).loadConfig(path: .value(projectPath)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(projectPath), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(feature)).willReturn(Set(["UIComponent"]))
        given(targetScanner).imports(for: .value(uiComponent)).willReturn(Set([]))

        // When / Then
        try await subject.run(path: projectPath.pathString, inspectionTypes: [.redundant])
    }
}
