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

final class LintImplicitImportsServiceTests: TuistUnitTestCase {
    private var configLoader: MockConfigLoading!
    private var generatorFactory: MockGeneratorFactorying!
    private var targetScanner: MockTargetImportsScanning!
    private var subject: InspectImplicitImportsService!
    private var generator: MockGenerating!

    override func setUp() {
        super.setUp()
        configLoader = MockConfigLoading()
        generatorFactory = MockGeneratorFactorying()
        targetScanner = MockTargetImportsScanning()
        generator = MockGenerating()
        subject = InspectImplicitImportsService(
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

        let expectedIssue = InspectImportsIssue(target: app.productName, dependencies: [framework.productName])
        let expectedError = InspectImportsServiceError.implicitImportsFound([expectedIssue])

        // When
        await XCTAssertThrowsSpecific(try await subject.run(path: path.pathString), expectedError)
    }

    func test_run_throwsAnError_when_transitiveLocalDependencyIsImplicitlyImported() async throws {
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
        await XCTAssertThrowsSpecific(
            try await subject.run(path: path.pathString),
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

    func test_run_when_external_package_target_is_implicitly_imported() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: path, targets: [app])
        let testTarget = Target.test(name: "PackageTarget", product: .app)
        let externalProject = Project.test(path: path, targets: [testTarget], type: .external(hash: "hash"))
        let graph = Graph.test(
            path: path,
            projects: [path: project, "/a": externalProject]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["PackageTarget"]))

        let expectedIssue = InspectImportsIssue(target: app.productName, dependencies: [testTarget.productName])
        let expectedError = InspectImportsServiceError.implicitImportsFound([expectedIssue])

        // When / Then
        await XCTAssertThrowsSpecific(try await subject.run(path: path.pathString), expectedError)
    }

    func test_run_when_external_package_target_is_explicitly_imported() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: path, targets: [app])
        let testTarget = Target.test(name: "PackageTarget", product: .app)
        let externalProject = Project.test(path: path, targets: [testTarget], type: .external(hash: "hash"))
        let graph = Graph.test(
            path: path,
            projects: [path: project, "/a": externalProject],
            dependencies: [GraphDependency.target(name: "App", path: path): Set([
                GraphDependency.target(name: "PackageTarget", path: "/a"),
            ])]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["PackageTarget"]))
        given(targetScanner).imports(for: .value(testTarget)).willReturn(Set())

        // When / Then
        try await subject.run(path: path.pathString)
    }

    func test_run_when_external_package_target_is_recursively_imported() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: path, targets: [app])

        let packagePath = try AbsolutePath(validating: "/a")
        let packageTarget = Target.test(name: "PackageTarget", product: .app)
        let packageTargetDependency = Target.test(name: "PackageTargetDependency", product: .app)
        let packageProject = Project.test(
            path: packagePath,
            targets: [packageTarget, packageTargetDependency],
            type: .external(hash: "hash")
        )
        let graph = Graph.test(
            path: path,
            projects: [path: project, packagePath: packageProject],
            dependencies: [
                GraphDependency.target(name: "App", path: path): Set([
                    GraphDependency.target(name: "PackageTarget", path: packagePath),
                ]),
                GraphDependency.target(name: "PackageTarget", path: packagePath): Set([
                    GraphDependency.target(name: "PackageTargetDependency", path: packagePath),
                ]),
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["PackageTargetDependency"]))

        // When / Then
        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowAnyErrors_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(
            path: path,

            projects: [path: project],
            dependencies: [.target(name: app.name, path: path): Set([.target(
                name: framework.name,
                path: path
            )])]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        // When
        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowErrorWithUnitTests_when_testExplicitlyDependsOnAppAndImportsIt() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let app = Target.test(
            name: "App",
            product: .app
        )

        let unitTests = Target.test(
            name: "AppTests",
            product: .unitTests,
            dependencies: [TargetDependency.target(name: "App")]
        )

        let project = Project.test(path: path, targets: [app, unitTests])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                .target(name: unitTests.name, path: project.path): [
                    .target(name: app.name, path: project.path),
                ],
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(unitTests)).willReturn(Set(["App"]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        // When
        try await subject.run(path: path.pathString)
    }

    func test_run_doesntThrowErrorWithUITests_when_testExplicitlyDependsOnAppAndImportsIt() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Tuist.test()

        let app = Target.test(
            name: "App",
            product: .app
        )

        let uiTests = Target.test(
            name: "AppUITests",
            product: .uiTests,
            dependencies: [TargetDependency.target(name: "App")]
        )

        let project = Project.test(path: path, targets: [app, uiTests])
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                .target(name: uiTests.name, path: project.path): [
                    .target(name: app.name, path: project.path),
                ],
            ]
        )

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), includedTargets: .any).willReturn(generator)
        given(generator).load(path: .value(path), options: .any).willReturn(graph)
        given(targetScanner).imports(for: .value(uiTests)).willReturn(Set(["App"]))
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))

        // When
        try await subject.run(path: path.pathString)
    }
}
