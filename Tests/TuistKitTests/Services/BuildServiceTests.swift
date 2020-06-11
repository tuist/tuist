import Foundation
import RxSwift
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class BuildServiceErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(BuildServiceError.schemeNotFound(scheme: "A", existing: ["B", "C"]).description, "Couldn't find scheme A. The available schemes are: B, C.")
        XCTAssertEqual(BuildServiceError.schemeWithoutBuildableTargets(scheme: "Scheme").description, "The scheme Scheme cannot be built because it contains no buildable targets.")
    }

    func test_type() {
        XCTAssertEqual(BuildServiceError.schemeNotFound(scheme: "A", existing: ["B", "C"]).type, .abort)
        XCTAssertEqual(BuildServiceError.schemeWithoutBuildableTargets(scheme: "Scheme").type, .abort)
    }
}

final class BuildServiceTests: TuistUnitTestCase {
    var projectGenerator: MockProjectGenerator!
    var xcodebuildController: MockXcodeBuildController!
    var buildgraphInspector: MockBuildGraphInspector!
    var subject: BuildService!

    override func setUp() {
        super.setUp()
        projectGenerator = MockProjectGenerator()
        xcodebuildController = MockXcodeBuildController()
        buildgraphInspector = MockBuildGraphInspector()
        subject = BuildService(projectGenerator: projectGenerator,
                               xcodebuildController: xcodebuildController,
                               buildGraphInspector: buildgraphInspector)
    }

    override func tearDown() {
        super.tearDown()
        projectGenerator = nil
        xcodebuildController = nil
        buildgraphInspector = nil
        subject = nil
    }

    func test_run_when_the_project_should_be_generated() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
        let scheme = Scheme.test()
        let target = Target.test()
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]

        projectGenerator.generateWithGraphStub = { _path, _projectOnly in
            XCTAssertEqual(_path, path)
            XCTAssertFalse(_projectOnly)
            return (path, graph)
        }
        buildgraphInspector.buildableSchemesStub = { _ in
            [scheme]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return target
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _target, _ in
            XCTAssertEqual(_target, target)
            return buildArguments
        }
        xcodebuildController.buildStub = { _target, _scheme, _clean, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_scheme, scheme.name)
            XCTAssertTrue(_clean)
            XCTAssertEqual(_arguments, buildArguments)
            return Observable.just(.standardOutput(.init(raw: "success", formatted: nil)))
        }

        // Then
        try subject.run(schemeName: scheme.name, generate: true, clean: true, configuration: nil, path: path)
    }

    func test_run_when_the_project_is_already_generated() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
        let scheme = Scheme.test()
        let target = Target.test()
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]

        projectGenerator.loadStub = { _path in
            XCTAssertEqual(_path, path)
            return graph
        }
        buildgraphInspector.buildableSchemesStub = { _ in
            [scheme]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return target
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _target, _ in
            XCTAssertEqual(_target, target)
            return buildArguments
        }
        xcodebuildController.buildStub = { _target, _scheme, _clean, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_scheme, scheme.name)
            XCTAssertTrue(_clean)
            XCTAssertEqual(_arguments, buildArguments)
            return Observable.just(.standardOutput(.init(raw: "success", formatted: nil)))
        }

        // Then
        try subject.run(schemeName: scheme.name, generate: false, clean: true, configuration: nil, path: path)
    }

    func test_run_only_cleans_the_first_time() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")
        let targetA = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]

        projectGenerator.loadStub = { _path in
            XCTAssertEqual(_path, path)
            return graph
        }
        buildgraphInspector.buildableSchemesStub = { _ in
            [schemeA, schemeB]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            if _scheme == schemeA { return targetA }
            else if _scheme == schemeB { return targetB }
            else { XCTFail("unexpected scheme"); return targetA }
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _, _ in
            buildArguments
        }
        xcodebuildController.buildStub = { _target, _scheme, _clean, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_arguments, buildArguments)

            if _scheme == "A" {
                XCTAssertEqual(_scheme, "A")
                XCTAssertTrue(_clean)
            } else if _scheme == "B" {
                // When running the second scheme clean should be false
                XCTAssertEqual(_scheme, "B")
                XCTAssertFalse(_clean)
            } else {
                XCTFail("unexpected scheme \(_scheme)")
            }
            return Observable.just(.standardOutput(.init(raw: "success", formatted: nil)))
        }

        // Then
        try subject.run(schemeName: nil, generate: false, clean: true, configuration: nil, path: path)
    }

    func test_run_only_runs_the_given_scheme_when_passed() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")
        let targetA = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]

        projectGenerator.loadStub = { _path in
            XCTAssertEqual(_path, path)
            return graph
        }
        buildgraphInspector.buildableSchemesStub = { _ in
            [schemeA, schemeB]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            if _scheme == schemeA { return targetA }
            else if _scheme == schemeB { return targetB }
            else { XCTFail("unexpected scheme"); return targetA }
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _, _ in
            buildArguments
        }
        xcodebuildController.buildStub = { _target, _scheme, _clean, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_arguments, buildArguments)

            if _scheme == "A" {
                XCTAssertEqual(_scheme, "A")
                XCTAssertTrue(_clean)
            } else {
                XCTFail("unexpected scheme \(_scheme)")
            }
            return Observable.just(.standardOutput(.init(raw: "success", formatted: nil)))
        }

        // Then
        try subject.run(schemeName: "A", generate: false, clean: true, configuration: nil, path: path)
    }
}
