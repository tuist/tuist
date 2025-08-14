import FileSystem
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

final class LintRedundantImportsServiceTests: TuistUnitTestCase {
    private var configLoader: MockConfigLoading!
    private var generatorFactory: MockGeneratorFactorying!
    private var targetScanner: MockTargetImportsScanning!
    private var subject: InspectRedundantImportsService!
    private var generator: MockGenerating!

    override func setUp() {
        super.setUp()
        configLoader = MockConfigLoading()
        generatorFactory = MockGeneratorFactorying()
        targetScanner = MockTargetImportsScanning()
        generator = MockGenerating()
        subject = InspectRedundantImportsService(
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

    func test_run_throwsAnError_when_thereAreIssues() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project")
            let config = Tuist.test()
            let framework = Target.test(name: "Framework", product: .framework)
            let app = Target.test(name: "App", product: .app, dependencies: [TargetDependency.target(name: "Framework")])
            let project = Project.test(path: path, targets: [app, framework])
            let graph = Graph.test(path: path, projects: [path: project], dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: framework.name, path: project.path),
                ],
            ])

            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
            given(generator).load(path: .value(path), options: .any).willReturn(graph)
            given(targetScanner).imports(for: .value(app)).willReturn(Set([]))
            given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

            // When
            await XCTAssertThrowsSpecific(try await subject.run(path: path.pathString), LintingError())
            XCTAssertStandardError(pattern: "App redundantly depends on: Framework")
        }
    }

    func test_run_throwsAnErrorButIgnoresIgnoredTags_when_thereAreIssues() async throws {
        try await withMockedDependencies {
            // Given
            let path = try AbsolutePath(validating: "/project")
            let config = Tuist.test(
                inspectOptions: .test(redundantDependencies: .init(ignoreTagsMatching: ["IgnoreRedundantDependencies"])),
            )
            let framework = Target.test(name: "Framework", product: .framework)
            let app = Target.test(
                name: "App",
                product: .app,
                dependencies: [TargetDependency.target(name: "Framework"), TargetDependency.target(name: "Framework2")],
                metadata: .metadata(tags: ["IgnoreRedundantDependencies"])
            )
            let framework2 = Target.test(
                name: "Framework2",
                product: .framework,
                dependencies: [TargetDependency.target(name: "Framework")]
            )
            let project = Project.test(path: path, targets: [app, framework, framework2])
            let graph = Graph.test(path: path, projects: [path: project], dependencies: [
                .target(name: app.name, path: project.path): [
                    .target(name: framework.name, path: project.path),
                    .target(name: framework2.name, path: project.path),
                ],
                .target(name: framework2.name, path: project.path): [
                    .target(name: framework.name, path: project.path),
                ],
            ])

            given(configLoader).loadConfig(path: .value(path)).willReturn(config)
            given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
            given(generator).load(path: .value(path), options: .any).willReturn(graph)
            given(targetScanner).imports(for: .value(app)).willReturn(Set([]))
            given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))
            given(targetScanner).imports(for: .value(framework2)).willReturn(Set([]))

            // When
            await XCTAssertThrowsSpecific(try await subject.run(path: path.pathString), LintingError())
            XCTAssertStandardError(pattern: "Framework2 redundantly depends on: Framework")
        }
    }

    func test_run_when_external_package_target_is_recursively_imported() async throws {
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
        given(targetScanner).imports(for: .value(app)).willReturn([])

        // When / Then
        await XCTAssertThrowsSpecific(try await subject.run(path: path.pathString), LintingError())
    }

    func test_run_doesntThrowAnyErrors_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app, dependencies: [TargetDependency.target(name: "Framework")])
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: framework.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        // When
        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowAnyErrorsWithBundle_when_thereAreNoIssues() async throws {
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

        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowAnyErrorsWithUITest_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let uiTests = Target.test(
            name: "UITests",
            product: .uiTests,
            dependencies: [TargetDependency.target(name: "App")]
        )

        let app = Target.test(
            name: "App",
            product: .app
        )
        let project = Project.test(path: path, targets: [uiTests, app])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: uiTests.name, path: project.path): [
                .target(name: app.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(uiTests)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowAnyErrorsWithAppExtensionsSetWithStickerPackExtension_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let appExtension = Target.test(
            name: "AppExtension",
            product: .appExtension
        )

        let stickerPackExtension = Target.test(
            name: "StickerPackExtension",
            product: .stickerPackExtension
        )

        let appIntentExtension = Target.test(
            name: "AppIntentExtension",
            product: .extensionKitExtension
        )

        let app = Target.test(
            name: "App",
            product: .app,
            dependencies: [
                TargetDependency.target(name: "AppExtension"),
                TargetDependency.target(name: "StickerPackExtension"),
                TargetDependency.target(name: "AppIntentExtension"),
            ]
        )
        let project = Project.test(path: path, targets: [appExtension, app])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: appExtension.name, path: project.path),
                .target(name: stickerPackExtension.name, path: project.path),
                .target(name: appIntentExtension.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(appExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(stickerPackExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(appIntentExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        try await subject.run(path: path.pathString)
    }

    /// We need a separate app to test out Message Extensions
    /// as having both stickers pack and message extensions in one app
    /// doesn't seem to be supported.
    func test_run_doesntThrowAnyErrorsWithAppExtensionsSetWithMessageExtension_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let appExtension = Target.test(
            name: "AppExtension",
            product: .appExtension
        )

        let messageExtension = Target.test(
            name: "MessageExtension",
            product: .messagesExtension
        )

        let app = Target.test(
            name: "App",
            product: .app,
            dependencies: [
                TargetDependency.target(name: "AppExtension"),
                TargetDependency.target(name: "MessageExtension"),
            ]
        )
        let project = Project.test(path: path, targets: [appExtension, app])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: appExtension.name, path: project.path),
                .target(name: messageExtension.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(appExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(messageExtension)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowAnyErrorsWithAppWithAppWatch_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let watch2App = Target.test(
            name: "Watch2App",
            product: .watch2App
        )

        let app = Target.test(
            name: "App",
            product: .app,
            dependencies: [
                TargetDependency.target(name: "Watch2App"),
            ]
        )
        let project = Project.test(path: path, targets: [watch2App, app])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: watch2App.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(watch2App)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowAnyErrorsWithWatchAppWithWatchExtension_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let watch2Extension = Target.test(
            name: "Watch2Extension",
            product: .watch2Extension
        )

        let app = Target.test(
            name: "App",
            product: .watch2App,
            dependencies: [
                TargetDependency.target(name: watch2Extension.name),
            ]
        )
        let project = Project.test(path: path, targets: [app, watch2Extension])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: watch2Extension.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(watch2Extension)).willReturn(Set([]))

        try await subject.run(path: path.pathString)
    }
}
