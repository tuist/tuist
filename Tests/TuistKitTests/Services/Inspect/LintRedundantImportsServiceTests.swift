import FileSystem
import Foundation
import Mockable
import MockableTest
import Path
import TuistCore
import TuistLoader
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistKit

final class LintRedundantImportsServiceTests: TuistUnitTestCase {
    private var configLoader: MockConfigLoading!
    private var generatorFactory: MockGeneratorFactorying!
    private var targetScanner: MockTargetImportsScanning!
    private var subject: InspectImportsService!
    private var generator: MockGenerating!

    override func setUp() async throws {
        try await super.setUp()
        configLoader = MockConfigLoading()
        generatorFactory = MockGeneratorFactorying()
        targetScanner = MockTargetImportsScanning()
        generator = MockGenerating()
        subject = InspectImportsService(
            generatorFactory: generatorFactory,
            configLoader: configLoader,
            targetScanner: targetScanner
        )
    }

    override func tearDown() async throws {
        configLoader = nil
        generatorFactory = nil
        targetScanner = nil
        generator = nil
        subject = nil
        try await super.tearDown()
    }

    func test_run_throwsAnError_when_thereAreIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Config.test()
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app, dependencies: [TargetDependency.target(name: "Framework")])
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: framework.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), sources: .any).willReturn(generator)
        given(generator).load(path: .value(path)).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set([]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        let expectedError = InspectRedundantImportsServiceError.redundantImportsFound([
            InspectImportsServiceErrorIssue(target: "App", implicitDependencies: Set(["Framework"])),
        ])

        // When
        await XCTAssertThrowsSpecific({ try await subject.run(path: path.pathString, inspectType: .redundant) }, expectedError)
    }

    func test_run_doesntThrowAnyErrors_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Config.test()
        let framework = Target.test(name: "Framework", product: .framework)
        let app = Target.test(name: "App", product: .app, dependencies: [TargetDependency.target(name: "Framework")])
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(path: path, projects: [path: project], dependencies: [
            .target(name: app.name, path: project.path): [
                .target(name: framework.name, path: project.path),
            ],
        ])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), sources: .any).willReturn(generator)
        given(generator).load(path: .value(path)).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn(Set(["Framework"]))
        given(targetScanner).imports(for: .value(framework)).willReturn(Set([]))

        // When
        try await subject.run(path: path.pathString, inspectType: .redundant)
    }
}
