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
    private var xcodebuildController: MockXcodeBuildController!
    private var buildGraphInspector: MockBuildGraphInspector!
    private var simulatorController: MockSimulatorController!

    override func setUpWithError() throws {
        try super.setUpWithError()
        generator = .init()
        xcodebuildController = .init()
        buildGraphInspector = .init()
        simulatorController = .init()

        subject = TestService(
            temporaryDirectory: try TemporaryDirectory(removeTreeOnDeinit: true),
            generator: generator,
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
            (Project.test(), Target.test(name: scheme.name))
        }
        generator.generateWithGraphStub = { path, _ in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _ in
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
        xcodebuildController.testStub = { _, scheme, _, _, _ in
            testedSchemes.append(scheme)
            return .just(.standardOutput(.init(raw: "success")))
        }

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
    }
}

// MARK: - Helpers

private extension TestService {
    func testRun(
        schemeName: String? = nil,
        generate _: Bool = false,
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
