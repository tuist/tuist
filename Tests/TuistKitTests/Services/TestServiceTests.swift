import Foundation
import RxSwift
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
    private var testServiceGeneratorFactory: MockTestServiceGeneratorFactory!
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
        testServiceGeneratorFactory = .init()
        testServiceGeneratorFactory.generatorStub = { _, _, _ in
            self.generator
        }
        let mockCacheDirectoriesProvider = try MockCacheDirectoriesProvider()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider

        contentHasher.hashStub = { _ in
            "hash"
        }

        subject = TestService(
            testsCacheTemporaryDirectory: testsCacheTemporaryDirectory,
            testServiceGeneratorFactory: testServiceGeneratorFactory,
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
        testServiceGeneratorFactory = nil
        contentHasher = nil
        subject = nil
        super.tearDown()
    }

    func test_run_uses_project_directory() throws {
        // Given
        var automationPath: AbsolutePath?

        testServiceGeneratorFactory.generatorStub = { gotAutomationPath, _, _ in
            automationPath = gotAutomationPath
            return self.generator
        }
        contentHasher.hashStub = {
            "\($0.replacingOccurrences(of: "/", with: ""))-hash"
        }

        // When
        try? subject.testRun(
            path: AbsolutePath("/test")
        )

        // Then
        XCTAssertEqual(
            automationPath,
            cacheDirectoriesProvider.cacheDirectory(for: .generatedAutomationProjects).appending(component: "test-hash")
        )
    }

    func test_run_generates_project() throws {
        // Given
        let path = try temporaryPath()
        var generatedPath: AbsolutePath?
        var projectOnly: Bool?
        generator.generateWithGraphStub = {
            generatedPath = $0
            projectOnly = $1
            return ($0, Graph.test())
        }

        // When
        try? subject.testRun(
            path: path
        )

        // Then
        XCTAssertEqual(generatedPath, path)
        XCTAssertEqual(projectOnly, false)
    }

    func test_run_tests_for_only_specified_scheme() throws {
        // Given
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "App-Project"),
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
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return .just(.standardOutput(.init(raw: "success")))
        }

        // When
        try subject.testRun(
            schemeName: "TestScheme",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["TestScheme"])
    }

    func test_run_tests_all_project_schemes() throws {
        // Given
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.projectSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
                Scheme.test(name: "ProjectSchemeTwo"),
            ]
        }
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return .just(.standardOutput(.init(raw: "success")))
        }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )

        // When
        try subject.testRun(
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

    func test_run_tests_all_project_schemes_when_fails() throws {
        // Given
        buildGraphInspector.projectSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
            ]
        }
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return .error(NSError.test())
        }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )

        // When / Then
        XCTAssertThrowsError(
            try subject.testRun(
                path: try temporaryPath()
            )
        )

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

    func test_run_tests_when_no_project_schemes_present() throws {
        // Given
        buildGraphInspector.projectSchemesStub = { _ in
            []
        }
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _ in
            testedSchemes.append(scheme)
            return .just(.standardOutput(.init(raw: "success")))
        }

        // When
        try subject.testRun(
            path: try temporaryPath()
        )

        // Then
        XCTAssertEmpty(testedSchemes)
        XCTAssertPrinterOutputContains("There are no tests to run, finishing early")
    }

    func test_run_uses_resource_bundle_path() throws {
        // Given
        let expectedResourceBundlePath = AbsolutePath("/test")
        var resourceBundlePath: AbsolutePath?

        xcodebuildController.testStub = { _, _, _, _, _, gotResourceBundlePath, _ in
            resourceBundlePath = gotResourceBundlePath
            return .empty()
        }
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        buildGraphInspector.projectSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
            ]
        }

        // When
        try subject.testRun(
            path: try temporaryPath(),
            resultBundlePath: expectedResourceBundlePath
        )

        // Then
        XCTAssertEqual(
            resourceBundlePath,
            expectedResourceBundlePath
        )
    }

    func test_run_uses_resource_bundle_path_with_given_scheme() throws {
        // Given
        let expectedResourceBundlePath = AbsolutePath("/test")
        var resourceBundlePath: AbsolutePath?

        xcodebuildController.testStub = { _, _, _, _, _, gotResourceBundlePath, _ in
            resourceBundlePath = gotResourceBundlePath
            return .empty()
        }
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        buildGraphInspector.projectSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
                Scheme.test(name: "ProjectScheme2"),
            ]
        }

        // When
        try subject.testRun(
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
}

// MARK: - Helpers

private extension TestService {
    func testRun(
        schemeName: String? = nil,
        clean: Bool = false,
        configuration: String? = nil,
        path: AbsolutePath,
        deviceName: String? = nil,
        osVersion: String? = nil,
        skipUiTests: Bool = false,
        resultBundlePath: AbsolutePath? = nil
    ) throws {
        try run(
            schemeName: schemeName,
            clean: clean,
            configuration: configuration,
            path: path,
            deviceName: deviceName,
            osVersion: osVersion,
            skipUITests: skipUiTests,
            resultBundlePath: resultBundlePath
        )
    }
}
