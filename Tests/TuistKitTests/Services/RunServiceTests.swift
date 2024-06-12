import Foundation
import MockableTest
import Path
import struct TSCUtility.Version
import TuistAutomation
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeGraphTesting
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
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var targetBuilder: MockTargetBuilder!
    private var targetRunner: MockTargetRunner!
    private var subject: RunService!

    private struct TestError: Equatable, Error {}

    override func setUp() {
        super.setUp()
        generator = .init()
        generatorFactory = MockGeneratorFactorying()
        given(generatorFactory)
            .defaultGenerator(config: .any)
            .willReturn(generator)
        buildGraphInspector = .init()
        targetBuilder = MockTargetBuilder()
        targetRunner = MockTargetRunner()
        subject = RunService(
            generatorFactory: generatorFactory,
            buildGraphInspector: buildGraphInspector,
            targetBuilder: targetBuilder,
            targetRunner: targetRunner
        )
    }

    override func tearDown() {
        generator = nil
        buildGraphInspector = nil
        targetBuilder = nil
        targetRunner = nil
        subject = nil
        generatorFactory = nil
        super.tearDown()
    }

    func test_run_generates_when_generateIsTrue() async throws {
        // Given
        given(generator)
            .generateWithGraph(path: .any)
            .willReturn((try AbsolutePath(validating: "/path/to/project.xcworkspace"), .test()))
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(try! AbsolutePath(validating: "/path/to/project.xcworkspace"))
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test()])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        try await subject.run(generate: true)
    }

    func test_run_generates_when_workspaceNotFound() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        given(generator)
            .generateWithGraph(path: .any)
            .willReturn((workspacePath, .test()))
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test()])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.run()
    }

    func test_run_buildsTarget() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let schemeName = "AScheme"
        let clean = true
        let configuration = "Test"
        targetBuilder
            .buildTargetStub = { _, _workspacePath, _scheme, _clean, _configuration, _, _, _, _, _, _, _ in
                // Then
                XCTAssertEqual(_workspacePath, workspacePath)
                XCTAssertEqual(_scheme.name, schemeName)
                XCTAssertEqual(_clean, clean)
                XCTAssertEqual(_configuration, configuration)
            }
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        targetRunner.assertCanRunTargetStub = { _ in }
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test(name: schemeName)])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.run(
            schemeName: schemeName,
            clean: clean,
            configuration: configuration
        )
    }

    func test_run_runsTarget() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/path/to/project.xcworkspace")
        let schemeName = "AScheme"
        let configuration = "Test"
        let minVersion = Target.test().deploymentTargets.configuredVersions.first?.versionString.version()
        let version = Version("15.0.0")
        let deviceName = "iPhone 11"
        let arguments = ["-arg1", "--arg2", "SomeArgument"]
        targetRunner
            .runTargetStub = { _, _workspacePath, _schemeName, _configuration, _minVersion, _version, _deviceName, _arguments in
                // Then
                XCTAssertEqual(_workspacePath, workspacePath)
                XCTAssertEqual(_schemeName, schemeName)
                XCTAssertEqual(_configuration, configuration)
                XCTAssertEqual(_minVersion, minVersion)
                XCTAssertEqual(_version, version)
                XCTAssertEqual(_deviceName, deviceName)
                XCTAssertEqual(_arguments, arguments)
            }
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        targetRunner.assertCanRunTargetStub = { _ in }
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test(name: schemeName)])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.run(
            schemeName: schemeName,
            configuration: configuration,
            device: deviceName,
            version: version.description,
            arguments: arguments
        )
    }

    func test_run_throws_beforeBuilding_if_cantRunTarget() async throws {
        // Given
        let workspacePath = try temporaryPath().appending(component: "App.xcworkspace")
        let expectation = expectation(description: "does not run target builder")
        expectation.isInverted = true
        given(generator)
            .load(path: .any)
            .willReturn(.test())
        given(buildGraphInspector)
            .workspacePath(directory: .any)
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .runnableSchemes(graphTraverser: .any)
            .willReturn([.test()])
        given(buildGraphInspector)
            .runnableTarget(scheme: .any, graphTraverser: .any)
            .willReturn(.test())
        targetBuilder.buildTargetStub = { _, _, _, _, _, _, _, _, _, _, _, _ in expectation.fulfill() }
        targetRunner.assertCanRunTargetStub = { _ in throw TestError() }

        // Then
        await XCTAssertThrowsSpecific(
            // When
            try await subject.run(),
            TestError()
        )
        await fulfillment(of: [expectation], timeout: 1)
    }
}

extension RunService {
    fileprivate func run(
        schemeName: String = Scheme.test().name,
        generate: Bool = false,
        clean: Bool = false,
        configuration: String? = nil,
        device: String? = nil,
        version: String? = nil,
        rosetta: Bool = false,
        arguments: [String] = []
    ) async throws {
        try await run(
            path: nil,
            schemeName: schemeName,
            generate: generate,
            clean: clean,
            configuration: configuration,
            device: device,
            version: version,
            rosetta: rosetta,
            arguments: arguments
        )
    }
}
