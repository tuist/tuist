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
    private var testsCacheTemporaryDirectory: TemporaryDirectory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        generator = .init()
        xcodebuildController = .init()
        buildGraphInspector = .init()
        simulatorController = .init()
        testsCacheTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        testServiceGeneratorFactory = .init()
        testServiceGeneratorFactory.generatorStub = { _, _ in
            self.generator
        }

        subject = TestService(
            temporaryDirectory: try TemporaryDirectory(removeTreeOnDeinit: true),
            testsCacheTemporaryDirectory: testsCacheTemporaryDirectory,
            testServiceGeneratorFactory: testServiceGeneratorFactory,
            xcodebuildController: xcodebuildController,
            buildGraphInspector: buildGraphInspector,
            simulatorController: simulatorController
        )
    }

    override func tearDown() {
        generator = nil
        xcodebuildController = nil
        buildGraphInspector = nil
        simulatorController = nil
        testsCacheTemporaryDirectory = nil
        testServiceGeneratorFactory = nil
        subject = nil
        super.tearDown()
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
            ValueGraphTarget.test(
                target: Target.test(
                    name: scheme.name
                )
            )
        }
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _ in
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
        xcodebuildController.testStub = { _, scheme, _, _, _, _ in
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
            fileHandler.exists(environment.testsCacheDirectory.appending(component: "A"))
        )
        XCTAssertTrue(
            fileHandler.exists(environment.testsCacheDirectory.appending(component: "B"))
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
        xcodebuildController.testStub = { _, scheme, _, _, _, _ in
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
            fileHandler.exists(environment.testsCacheDirectory.appending(component: "A"))
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
        xcodebuildController.testStub = { _, scheme, _, _, _, _ in
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
}

// MARK: - Helpers

private extension TestService {
    func testRun(
        schemeName: String? = nil,
        clean: Bool = false,
        configuration: String? = nil,
        path: AbsolutePath,
        deviceName: String? = nil,
        osVersion: String? = nil
    ) throws {
        try run(
            schemeName: schemeName,
            clean: clean,
            configuration: configuration,
            path: path,
            deviceName: deviceName,
            osVersion: osVersion
        )
    }
}
