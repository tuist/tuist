import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class BuildServiceErrorTests: TuistUnitTestCase {
    func test_description() {
        XCTAssertEqual(
            BuildServiceError.schemeNotFound(scheme: "A", existing: ["B", "C"]).description,
            "Couldn't find scheme A. The available schemes are: B, C."
        )
        XCTAssertEqual(
            BuildServiceError.schemeWithoutBuildableTargets(scheme: "MyScheme").description,
            "The scheme MyScheme cannot be built because it contains no buildable targets."
        )
        XCTAssertEqual(
            BuildServiceError.workspaceNotFound(path: "/path/to/workspace").description,
            "Workspace not found expected xcworkspace at /path/to/workspace"
        )
    }

    func test_type() {
        XCTAssertEqual(BuildServiceError.schemeNotFound(scheme: "A", existing: ["B", "C"]).type, .abort)
        XCTAssertEqual(BuildServiceError.schemeWithoutBuildableTargets(scheme: "MyScheme").type, .abort)
        XCTAssertEqual(BuildServiceError.workspaceNotFound(path: "/path/to/workspace").type, .bug)
    }
}

final class BuildServiceTests: TuistUnitTestCase {
    var generator: MockGenerator!
    var buildGraphInspector: MockBuildGraphInspector!
    var targetBuilder: MockTargetBuilder!
    var subject: BuildService!

    override func setUp() {
        super.setUp()
        generator = MockGenerator()
        buildGraphInspector = MockBuildGraphInspector()
        targetBuilder = MockTargetBuilder()
        subject = BuildService(
            generator: generator,
            buildGraphInspector: buildGraphInspector,
            targetBuilder: targetBuilder
        )
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        buildGraphInspector = nil
        targetBuilder = nil
        subject = nil
    }

    func test_run_when_the_project_should_be_generated() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = ValueGraph.test()
        let scheme = Scheme.test()
        let project = Project.test()
        let target = Target.test()
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
        let skipSigning = false

        generator.generateWithGraphStub = { _path, _projectOnly in
            XCTAssertEqual(_path, path)
            XCTAssertFalse(_projectOnly)
            return (path, graph)
        }
        buildGraphInspector.buildableSchemesStub = { _ in
            [scheme]
        }
        buildGraphInspector.buildableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return ValueGraphTarget.test(path: project.path, target: target, project: project)
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _project, _target, _, _skipSigning in
            XCTAssertEqual(_project, project)
            XCTAssertEqual(_target, target)
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        targetBuilder.buildTargetStub = { _, _workspacePath, _schemeName, _clean, _, _ in
            XCTAssertEqual(_workspacePath, workspacePath)
            XCTAssertEqual(_schemeName, scheme.name)
            XCTAssertTrue(_clean)
        }

        // Then
        try subject.testRun(
            schemeName: scheme.name,
            path: path
        )
    }

    func test_run_when_the_project_is_already_generated() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = ValueGraph.test()
        let scheme = Scheme.test()
        let project = Project.test()
        let target = Target.test()
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
        let skipSigning = false

        generator.loadStub = { _path in
            XCTAssertEqual(_path, path)
            return graph
        }
        buildGraphInspector.buildableSchemesStub = { _ in
            [scheme]
        }
        buildGraphInspector.buildableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return ValueGraphTarget.test(path: project.path, target: target, project: project)
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _project, _target, _, _skipSigning in
            XCTAssertEqual(_project, project)
            XCTAssertEqual(_target, target)
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        targetBuilder.buildTargetStub = { _, _workspacePath, _schemeName, _clean, _, _ in
            XCTAssertEqual(_workspacePath, workspacePath)
            XCTAssertEqual(_schemeName, scheme.name)
            XCTAssertTrue(_clean)
        }

        // Then
        try subject.testRun(
            schemeName: scheme.name,
            path: path
        )
    }

    func test_run_only_cleans_the_first_time() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = ValueGraph.test()
        let project = Project.test()
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")
        let targetA = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
        let skipSigning = false

        generator.loadStub = { _path in
            XCTAssertEqual(_path, path)
            return graph
        }
        buildGraphInspector.buildableSchemesStub = { _ in
            [schemeA, schemeB]
        }
        buildGraphInspector.buildableTargetStub = { _scheme, _ in
            if _scheme == schemeA { return ValueGraphTarget.test(path: project.path, target: targetA, project: project) }
            else if _scheme == schemeB { return ValueGraphTarget.test(path: project.path, target: targetB, project: project) }
            else { XCTFail("unexpected scheme"); return ValueGraphTarget.test(path: project.path, target: targetA, project: project) }
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _, _, _, _skipSigning in
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        targetBuilder.buildTargetStub = { _, _workspacePath, _schemeName, _clean, _, _ in
            XCTAssertEqual(_workspacePath, workspacePath)

            if _schemeName == "A" {
                XCTAssertEqual(_schemeName, schemeA.name)
                XCTAssertTrue(_clean)
            } else if _schemeName == "B" {
                // When running the second scheme clean should be false
                XCTAssertEqual(_schemeName, schemeB.name)
                XCTAssertFalse(_clean)
            } else {
                XCTFail("unexpected scheme \(_schemeName)")
            }
        }

        // Then
        try subject.testRun(
            path: path
        )
    }

    func test_run_only_builds_the_given_scheme_when_passed() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = ValueGraph.test()
        let project = Project.test()
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")
        let targetA = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
        let skipSigning = false

        generator.loadStub = { _path in
            XCTAssertEqual(_path, path)
            return graph
        }
        buildGraphInspector.buildableSchemesStub = { _ in
            [schemeA, schemeB]
        }
        buildGraphInspector.buildableTargetStub = { _scheme, _ in
            if _scheme == schemeA { return ValueGraphTarget.test(path: project.path, target: targetA, project: project) }
            else if _scheme == schemeB { return ValueGraphTarget.test(path: project.path, target: targetB, project: project) }
            else { XCTFail("unexpected scheme"); return ValueGraphTarget.test(path: project.path, target: targetA, project: project) }
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _, _, _, _skipSigning in
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        targetBuilder.buildTargetStub = { _, _workspacePath, _schemeName, _clean, _, _ in
            XCTAssertEqual(_workspacePath, workspacePath)

            if _schemeName == "A" {
                XCTAssertEqual(_schemeName, schemeA.name)
                XCTAssertTrue(_clean)
            } else {
                XCTFail("unexpected scheme \(_schemeName)")
            }
        }

        // Then
        try subject.testRun(
            schemeName: "A",
            path: path
        )
    }

    func test_run_lists_schemes() throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = ValueGraph.test()
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")
        generator.loadStub = { _path in
            XCTAssertEqual(_path, path)
            return graph
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildGraphInspector.buildableSchemesStub = { _ in
            [
                schemeA,
                schemeB,
            ]
        }

        // When
        try subject.testRun(
            path: path
        )

        // Then
        XCTAssertPrinterContains("Found the following buildable schemes: A, B", at: .debug, ==)
    }
}

// MARK: - Helpers

private extension BuildService {
    func testRun(
        schemeName: String? = nil,
        generate: Bool = false,
        clean: Bool = true,
        configuration: String? = nil,
        buildOutputPath: AbsolutePath? = nil,
        path: AbsolutePath
    ) throws {
        try run(
            schemeName: schemeName,
            generate: generate,
            clean: clean,
            configuration: configuration,
            buildOutputPath: buildOutputPath,
            path: path
        )
    }
}
