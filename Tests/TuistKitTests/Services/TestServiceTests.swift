import Foundation
import RxSwift
import TSCBasic
import TuistAutomation
import TuistCore
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

    override func setUp() {
        super.setUp()
        generator = .init()
        xcodebuildController = .init()
        buildGraphInspector = .init()
        simulatorController = .init()

        subject = TestService(
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

    func test_run_when_the_project_is_already_generated() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test(
            workspace: .test(
                path: workspacePath,
                name: "App"
            )
        )
        let scheme = Scheme.test(name: "App-Project")
        let target = Target.test()
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
        let skipSigning = true

        generator.generateWithGraphStub = { _path, projectOnly in
            XCTAssertEqual(_path, path)
            XCTAssertFalse(projectOnly)
            return (_path, graph)
        }
        buildGraphInspector.testableSchemesStub = { _ in
            [scheme]
        }
        buildGraphInspector.testableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return target
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, workspacePath)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _target, _, _skipSigning in
            XCTAssertEqual(_target, target)
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }

        let availableDeviceAndRuntime: SimulatorDeviceAndRuntime = .test()
        simulatorController.findAvailableDeviceStub = { _, _, _, _ in
            .just(availableDeviceAndRuntime)
        }
        xcodebuildController.testStub = { _target, _scheme, _clean, _destination, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_scheme, scheme.name)
            XCTAssertTrue(_clean)
            XCTAssertEqual(_arguments, buildArguments)
            XCTAssertEqual(_destination, .device(availableDeviceAndRuntime.device.udid))
            return Observable.just(.standardOutput(.init(raw: "success", formatted: nil)))
        }

        // Then
        try subject.testRun(
            schemeName: scheme.name,
            clean: true,
            path: path
        )
    }

    func test_run_only_when_scheme_specified() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test(
            workspace: .test(
                path: workspacePath
            )
        )
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")
        let targetA = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
        let skipSigning = true

        generator.generateWithGraphStub = { _path, projectOnly in
            XCTAssertEqual(_path, path)
            XCTAssertFalse(projectOnly)
            return (_path, graph)
        }
        buildGraphInspector.testableSchemesStub = { _ in
            [schemeA, schemeB]
        }
        buildGraphInspector.buildableTargetStub = { _scheme, _ in
            if _scheme == schemeA { return targetA }
            else if _scheme == schemeB { return targetB }
            else { XCTFail("unexpected scheme"); return targetA }
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, workspacePath)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _, _, _skipSigning in
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        xcodebuildController.testStub = { _target, _scheme, _clean, _, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_arguments, buildArguments)
            XCTAssertEqual(_scheme, "B")
            XCTAssertTrue(_clean)
            return Observable.just(.standardOutput(.init(raw: "success", formatted: nil)))
        }

        // Then
        try subject.testRun(
            schemeName: "B",
            clean: true,
            path: path
        )
    }

    func test_run_lists_schemes() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test(
            workspace: .test(
                path: workspacePath,
                name: "App"
            )
        )
        let scheme = Scheme.test(name: "App-Project")
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")
        generator.generateWithGraphStub = { _path, projectOnly in
            XCTAssertEqual(_path, path)
            XCTAssertFalse(projectOnly)
            return (_path, graph)
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, workspacePath)
            return workspacePath
        }
        buildGraphInspector.testableSchemesStub = { _ in
            [
                scheme,
                schemeA,
                schemeB,
            ]
        }
        xcodebuildController.testStub = { _, _, _, _, _ in
            .just(.standardOutput(.init(raw: "success", formatted: nil)))
        }

        // When
        try subject.testRun(
            path: path
        )

        // Then
        XCTAssertPrinterContains("Found the following testable schemes: App-Project, A, B", at: .debug, ==)
    }
}

// MARK: - Helpers

private extension TestService {
    func testRun(
        schemeName: String? = nil,
        generate: Bool = false,
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
