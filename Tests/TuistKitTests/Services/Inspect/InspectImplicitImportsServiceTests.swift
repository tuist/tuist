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

final class InspectImplicitImportsServiceTests: TuistUnitTestCase {
    private var configLoader: MockConfigLoading!
    private var generatorFactory: MockGeneratorFactorying!
    private var targetScanner: MockTargetImportsScanning!
    private var subject: InspectImplicitImportsService!
    private var generator: MockGenerating!

    override func setUp() async throws {
        try await super.setUp()
        configLoader = MockConfigLoading()
        generatorFactory = MockGeneratorFactorying()
        targetScanner = MockTargetImportsScanning()
        generator = MockGenerating()
        subject = InspectImplicitImportsService(
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
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let graph = Graph.test(path: path, projects: [path: project])

        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(generatorFactory).defaultGenerator(config: .value(config), sources: .any).willReturn(generator)
        given(generator).load(path: .value(path)).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn([ModuleImport(module: "Framework", line: 1, file: path)])
        given(targetScanner).imports(for: .value(framework)).willReturn([])

        let expectedError = InspectImplicitImportsServiceError.implicitImportsFound(
            [" - App implicitly depends on: Framework"]
        )

        // When
        await XCTAssertThrowsSpecific({ try await subject.run(
            path: path.pathString,
            xcode: false,
            strict: true
        ) }, expectedError)
    }

    func test_run_doesntThrowAnyErrors_when_thereAreNoIssues() async throws {
        // Given
        let path = try AbsolutePath(validating: "/project")
        let config = Config.test()
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
        given(generatorFactory).defaultGenerator(config: .value(config), sources: .any).willReturn(generator)
        given(generator).load(path: .value(path)).willReturn(graph)
        given(targetScanner).imports(for: .value(app)).willReturn([])
        given(targetScanner).imports(for: .value(framework)).willReturn([])

        // When
        try await subject.run(
            path: path.pathString,
            xcode: false,
            strict: true
        )
    }
}
