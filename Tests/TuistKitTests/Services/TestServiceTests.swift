import Foundation
import TSCBasic
import TuistAutomation
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class TestServiceTests: TuistUnitTestCase {
    private var subject: TestService!
    private var generator: MockGenerator!
    private var generatorFactory: MockGeneratorFactory!
    private var xcodebuildController: MockXcodeBuildController!
    private var buildGraphInspector: MockBuildGraphInspector!
    private var simulatorController: MockSimulatorController!
    private var contentHasher: MockContentHasher!
    private var testsCacheTemporaryDirectory: TemporaryDirectory!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        generator = .init()
        xcodebuildController = .init()
        buildGraphInspector = .init()
        simulatorController = .init()
        contentHasher = .init()
        testsCacheTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        generatorFactory = .init()
        generatorFactory.stubbedTestResult = generator
        let mockCacheDirectoriesProvider = try MockCacheDirectoriesProvider()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider

        contentHasher.hashStub = { _ in
            "hash"
        }

        subject = TestService(
            testsCacheTemporaryDirectory: testsCacheTemporaryDirectory,
            generatorFactory: generatorFactory,
            xcodebuildController: xcodebuildController,
            buildGraphInspector: buildGraphInspector,
            simulatorController: simulatorController,
            contentHasher: contentHasher,
            cacheDirectoryProviderFactory: MockCacheDirectoriesProviderFactory(provider: mockCacheDirectoriesProvider)
        )
    }

    override func tearDown() {
        generator = nil
        xcodebuildController = nil
        buildGraphInspector = nil
        simulatorController = nil
        testsCacheTemporaryDirectory = nil
        generatorFactory = nil
        contentHasher = nil
        subject = nil
        super.tearDown()
    }

    func test_run_uses_project_directory() async throws {
        // Given
        contentHasher.hashStub = {
            "\($0.replacingOccurrences(of: "/", with: ""))-hash"
        }

        // When
        try? await subject.testRun(
            path: try AbsolutePath(validating: "/test")
        )

        // Then
        let gotPath = generatorFactory.invokedTestParametersList.first?.automationPath
        XCTAssertEqual(
            gotPath,
            cacheDirectoriesProvider.cacheDirectory(for: .generatedAutomationProjects).appending(component: "test-hash")
        )
    }

    func test_run_generates_project() async throws {
        // Given
        let path = try temporaryPath()
        var generatedPath: AbsolutePath?
        generator.generateWithGraphStub = {
            generatedPath = $0
            return ($0, Graph.test())
        }

        // When
        try? await subject.testRun(
            path: path
        )

        // Then
        XCTAssertEqual(generatedPath, path)
    }

    func test_run_tests_for_only_specified_scheme() async throws {
        // Given
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "App-Workspace"),
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.testableTargetStub = { scheme, _ in
            GraphTarget.test(
                target: Target.test(
                    name: scheme.name
                )
            )
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return [.standardOutput(.init(raw: "success"))]
        }

        // When
        try await subject.testRun(
            schemeName: "TestScheme",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["TestScheme"])
    }

    func test_run_tests_all_project_schemes() async throws {
        // Given
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
                Scheme.test(name: "ProjectSchemeTwo"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return [.standardOutput(.init(raw: "success"))]
        }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )

        // When
        try await subject.testRun(
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(
            testedSchemes,
            [
                "ProjectSchemeOne",
                "ProjectSchemeTwo",
            ]
        )
        XCTAssertTrue(
            fileHandler.exists(cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: "A"))
        )
        XCTAssertTrue(
            fileHandler.exists(cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: "B"))
        )
    }

    func test_run_tests_individual_scheme() async throws {
        // Given
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
                Scheme.test(name: "ProjectSchemeTwo"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return [.standardOutput(.init(raw: "success"))]
        }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["ProjectSchemeOne"])
        XCTAssertTrue(
            fileHandler.exists(cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: "A"))
        )
        XCTAssertTrue(
            fileHandler.exists(cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: "B"))
        )
    }

    func test_run_tests_all_project_schemes_when_fails() async throws {
        // Given
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testErrorStub = NSError.test()
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return []
        }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )

        // When / Then
        do {
            try await subject.testRun(
                path: try temporaryPath()
            )
            XCTFail("Should throw")
        } catch {}
        XCTAssertEqual(
            testedSchemes,
            [
                "ProjectScheme",
            ]
        )
        XCTAssertFalse(
            fileHandler.exists(cacheDirectoriesProvider.cacheDirectory(for: .tests).appending(component: "A"))
        )
    }

    func test_run_tests_when_no_project_schemes_present() async throws {
        // Given
        buildGraphInspector.workspaceSchemesStub = { _ in
            []
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return [.standardOutput(.init(raw: "success"))]
        }

        // When
        try await subject.testRun(
            path: try temporaryPath()
        )

        // Then
        XCTAssertEmpty(testedSchemes)
        XCTAssertPrinterOutputContains("There are no tests to run, finishing early")
    }

    func test_run_uses_resource_bundle_path() async throws {
        // Given
        let expectedResourceBundlePath = try AbsolutePath(validating: "/test")
        var resourceBundlePath: AbsolutePath?

        xcodebuildController.testStub = { _, _, _, _, _, gotResourceBundlePath, _, _ in
            resourceBundlePath = gotResourceBundlePath
            return []
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
            ]
        }

        // When
        try await subject.testRun(
            path: try temporaryPath(),
            resultBundlePath: expectedResourceBundlePath
        )

        // Then
        XCTAssertEqual(
            resourceBundlePath,
            expectedResourceBundlePath
        )
    }

    func test_run_uses_resource_bundle_path_with_given_scheme() async throws {
        // Given
        let expectedResourceBundlePath = try AbsolutePath(validating: "/test")
        var resourceBundlePath: AbsolutePath?

        xcodebuildController.testStub = { _, _, _, _, _, gotResourceBundlePath, _, _ in
            resourceBundlePath = gotResourceBundlePath
            return []
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
                Scheme.test(name: "ProjectScheme2"),
            ]
        }

        // When
        try await subject.testRun(
            schemeName: "ProjectScheme2",
            path: try temporaryPath(),
            resultBundlePath: expectedResourceBundlePath
        )

        // Then
        XCTAssertEqual(
            resourceBundlePath,
            expectedResourceBundlePath
        )
    }

    func test_run_passes_retry_count_as_argument() async throws {
        // Given
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }

        var passedRetryCount = 0
        xcodebuildController.testStub = { _, _, _, _, _, _, _, retryCount in
            passedRetryCount = retryCount
            return [.standardOutput(.init(raw: "success"))]
        }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath(),
            retryCount: 3
        )

        // Then
        XCTAssertEqual(passedRetryCount, 3)
    }

    func test_run_defaults_retry_count_to_zero() async throws {
        // Given
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }

        var passedRetryCount = -1
        xcodebuildController.testStub = { _, _, _, _, _, _, _, retryCount in
            passedRetryCount = retryCount
            return [.standardOutput(.init(raw: "success"))]
        }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(passedRetryCount, 0)
    }
}

// MARK: - Helpers

extension TestService {
    fileprivate func testRun(
        schemeName: String? = nil,
        clean: Bool = false,
        configuration: String? = nil,
        path: AbsolutePath,
        deviceName: String? = nil,
        osVersion: String? = nil,
        skipUiTests: Bool = false,
        resultBundlePath: AbsolutePath? = nil,
        retryCount: Int = 0
    ) async throws {
        try await run(
            schemeName: schemeName,
            clean: clean,
            configuration: configuration,
            path: path,
            deviceName: deviceName,
            osVersion: osVersion,
            skipUITests: skipUiTests,
            resultBundlePath: resultBundlePath,
            retryCount: retryCount
        )
    }
}
