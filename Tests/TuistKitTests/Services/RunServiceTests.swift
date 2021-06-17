import Foundation
import RxSwift
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class RunServiceErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(
            RunServiceError.schemeNotFound(scheme: "Scheme", existing: ["A", "B"]).description,
            "Couldn't find scheme Scheme. The available schemes are: A, B."
        )
        XCTAssertEqual(
            RunServiceError.schemeWithoutRunnableTarget(scheme: "Scheme").description,
            "The scheme Scheme cannot be run because it contains no runnable target."
        )
        XCTAssertEqual(
            RunServiceError.invalidVersion("1.0.0").description,
            "The version 1.0.0 is not a valid version specifier."
        )
    }

    func test_type() {
        XCTAssertEqual(RunServiceError.schemeNotFound(scheme: "Scheme", existing: ["A", "B"]).type, .abort)
        XCTAssertEqual(RunServiceError.schemeWithoutRunnableTarget(scheme: "Scheme").type, .abort)
        XCTAssertEqual(RunServiceError.invalidVersion("1.0.0").type, .abort)
    }
}

final class RunServiceTests: TuistUnitTestCase {
    var generator: MockGenerator!
    var buildGraphInspector: MockBuildGraphInspector!
    var targetBuilder: MockTargetBuilder!
    var targetRunner: MockTargetRunner!
    var subject: RunService!

    private struct TestError: Equatable, Error {}

    override func setUp() {
        generator = MockGenerator()
        buildGraphInspector = MockBuildGraphInspector()
        targetBuilder = MockTargetBuilder()
        targetRunner = MockTargetRunner()
        subject = RunService(
            generator: generator,
            buildGraphInspector: buildGraphInspector,
            targetBuilder: targetBuilder,
            targetRunner: targetRunner
        )
        super.setUp()
    }

    override func tearDown() {
        generator = nil
        buildGraphInspector = nil
        targetBuilder = nil
        targetRunner = nil
        subject = nil
        super.tearDown()
    }

    func test_run_generates_when_generateIsTrue() throws {
        // Given
        let expectation = self.expectation(description: "generates when required")
        generator.generateWithGraphStub = { _, _projectOnly in
            XCTAssertFalse(_projectOnly)
            expectation.fulfill()
            return (AbsolutePath("/path/to/project.xcworkspace"), .test())
        }
        buildGraphInspector.workspacePathStub = { _ in AbsolutePath("/path/to/project.xcworkspace") }
        buildGraphInspector.runnableSchemesStub = { _ in [.test()] }
        buildGraphInspector.runnableTargetStub = { _, _ in .test() }

        try subject.run(generate: true)
        waitForExpectations(timeout: 1)
    }

    func test_run_generates_when_workspaceNotFound() throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let expectation = self.expectation(description: "generates when required")
        generator.generateWithGraphStub = { _, _projectOnly in
            // Then
            XCTAssertFalse(_projectOnly)
            self.buildGraphInspector.workspacePathStub = { _ in workspacePath }
            expectation.fulfill()
            return (workspacePath, .test())
        }
        buildGraphInspector.workspacePathStub = { _ in nil }
        buildGraphInspector.runnableSchemesStub = { _ in [.test()] }
        buildGraphInspector.runnableTargetStub = { _, _ in .test() }

        // When
        try subject.run()
        waitForExpectations(timeout: 1)
    }

    func test_run_buildsTarget() throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let expectation = self.expectation(description: "builds target")
        let schemeName = "AScheme"
        let clean = true
        let configuration = "Test"
        targetBuilder.buildTargetStub = { _, _workspacePath, _schemeName, _clean, _configuration, _ in
            // Then
            XCTAssertEqual(_workspacePath, workspacePath)
            XCTAssertEqual(_schemeName, schemeName)
            XCTAssertEqual(_clean, clean)
            XCTAssertEqual(_configuration, configuration)
            expectation.fulfill()
        }
        generator.generateWithGraphStub = { _, _ in (workspacePath, .test()) }
        targetRunner.assertCanRunTargetStub = { _ in }
        buildGraphInspector.workspacePathStub = { _ in workspacePath }
        buildGraphInspector.runnableSchemesStub = { _ in [.test(name: schemeName)] }
        buildGraphInspector.runnableTargetStub = { _, _ in .test() }

        // When
        try subject.run(
            schemeName: schemeName,
            clean: clean,
            configuration: configuration
        )
        waitForExpectations(timeout: 1)
    }

    func test_run_runsTarget() throws {
        // Given
        let workspacePath = AbsolutePath("/path/to/project.xcworkspace")
        let expectation = self.expectation(description: "runs target")
        let schemeName = "AScheme"
        let configuration = "Test"
        let minVersion = Target.test().deploymentTarget?.version.version()
        let version = Version(string: "15.0.0")
        let deviceName = "iPhone 11"
        let arguments = ["-arg1", "--arg2", "SomeArgument"]
        targetRunner.runTargetStub = { _, _workspacePath, _schemeName, _configuration, _minVersion, _version, _deviceName, _arguments in
            // Then
            XCTAssertEqual(_workspacePath, workspacePath)
            XCTAssertEqual(_schemeName, schemeName)
            XCTAssertEqual(_configuration, configuration)
            XCTAssertEqual(_minVersion, minVersion)
            XCTAssertEqual(_version, version)
            XCTAssertEqual(_deviceName, deviceName)
            XCTAssertEqual(_arguments, arguments)
            expectation.fulfill()
        }
        generator.generateWithGraphStub = { _, _ in (workspacePath, .test()) }
        targetRunner.assertCanRunTargetStub = { _ in }
        buildGraphInspector.workspacePathStub = { _ in workspacePath }
        buildGraphInspector.runnableSchemesStub = { _ in [.test(name: schemeName)] }
        buildGraphInspector.runnableTargetStub = { _, _ in .test() }

        // When
        try subject.run(
            schemeName: schemeName,
            configuration: configuration,
            device: deviceName,
            version: version?.description,
            arguments: arguments
        )
        waitForExpectations(timeout: 1)
    }

    func test_run_throws_beforeBuilding_if_cantRunTarget() throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let expectation = self.expectation(description: "does not run target builder")
        expectation.isInverted = true
        generator.generateWithGraphStub = { _, _ in (workspacePath, .test()) }
        buildGraphInspector.workspacePathStub = { _ in workspacePath }
        buildGraphInspector.runnableSchemesStub = { _ in [.test()] }
        buildGraphInspector.runnableTargetStub = { _, _ in .test() }
        targetBuilder.buildTargetStub = { _, _, _, _, _, _ in expectation.fulfill() }
        targetRunner.assertCanRunTargetStub = { _ in throw TestError() }

        // Then
        XCTAssertThrowsSpecific(
            // When
            try subject.run(),
            TestError()
        )
        waitForExpectations(timeout: 1)
    }
}

private extension RunService {
    func run(
        schemeName: String = Scheme.test().name,
        generate: Bool = false,
        clean: Bool = false,
        configuration: String? = nil,
        device: String? = nil,
        version: String? = nil,
        arguments: [String] = []
    ) throws {
        try run(
            path: nil,
            schemeName: schemeName,
            generate: generate,
            clean: clean,
            configuration: configuration,
            device: device,
            version: version,
            arguments: arguments
        )
    }
}
