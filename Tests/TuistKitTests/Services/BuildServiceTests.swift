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
        XCTAssertEqual(BuildServiceError.schemeNotFound(scheme: "A", existing: ["B", "C"]).description, "Couldn't find scheme A. The available schemes are: B, C.")
        XCTAssertEqual(BuildServiceError.schemeWithoutBuildableTargets(scheme: "Scheme").description, "The scheme Scheme cannot be built because it contains no buildable targets.")
    }

    func test_type() {
        XCTAssertEqual(BuildServiceError.schemeNotFound(scheme: "A", existing: ["B", "C"]).type, .abort)
        XCTAssertEqual(BuildServiceError.schemeWithoutBuildableTargets(scheme: "Scheme").type, .abort)
    }
}

final class BuildServiceTests: TuistUnitTestCase {
    var generator: MockGenerator!
    var xcodeBuildController: MockXcodeBuildController!
    var buildgraphInspector: MockBuildGraphInspector!
    var xcodeProjectBuildDirectoryLocator: MockXcodeProjectBuildDirectoryLocator!
    var subject: BuildService!

    override func setUp() {
        super.setUp()
        generator = MockGenerator()
        xcodeBuildController = MockXcodeBuildController()
        buildgraphInspector = MockBuildGraphInspector()
        xcodeProjectBuildDirectoryLocator = MockXcodeProjectBuildDirectoryLocator()
        subject = BuildService(
            generator: generator,
            xcodeBuildController: xcodeBuildController,
            xcodeProjectBuildDirectoryLocator: xcodeProjectBuildDirectoryLocator,
            buildGraphInspector: buildgraphInspector
        )
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        xcodeBuildController = nil
        buildgraphInspector = nil
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
        buildgraphInspector.buildableSchemesStub = { _ in
            [scheme]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return (project, target)
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _project, _target, _, _skipSigning in
            XCTAssertEqual(_project, project)
            XCTAssertEqual(_target, target)
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        xcodeBuildController.buildStub = { _target, _scheme, _clean, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_scheme, scheme.name)
            XCTAssertTrue(_clean)
            XCTAssertEqual(_arguments, buildArguments)
            return Observable.just(.standardOutput(.init(raw: "success")))
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
        buildgraphInspector.buildableSchemesStub = { _ in
            [scheme]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return (project, target)
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _project, _target, _, _skipSigning in
            XCTAssertEqual(_project, project)
            XCTAssertEqual(_target, target)
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        xcodeBuildController.buildStub = { _target, _scheme, _clean, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_scheme, scheme.name)
            XCTAssertTrue(_clean)
            XCTAssertEqual(_arguments, buildArguments)
            return Observable.just(.standardOutput(.init(raw: "success")))
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
        buildgraphInspector.buildableSchemesStub = { _ in
            [schemeA, schemeB]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            if _scheme == schemeA { return (project, targetA) }
            else if _scheme == schemeB { return (project, targetB) }
            else { XCTFail("unexpected scheme"); return (project, targetA) }
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _, _, _, _skipSigning in
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        xcodeBuildController.buildStub = { _target, _scheme, _clean, _arguments in
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
            return Observable.just(.standardOutput(.init(raw: "success")))
        }

        // Then
        try subject.testRun(
            path: path
        )
    }

    func test_run_only_runs_the_given_scheme_when_passed() throws {
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
        buildgraphInspector.buildableSchemesStub = { _ in
            [schemeA, schemeB]
        }
        buildgraphInspector.buildableTargetStub = { _scheme, _ in
            if _scheme == schemeA { return (project, targetA) }
            else if _scheme == schemeB { return (project, targetB) }
            else { XCTFail("unexpected scheme"); return (project, targetA) }
        }
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildArgumentsStub = { _, _, _, _skipSigning in
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        xcodeBuildController.buildStub = { _target, _scheme, _clean, _arguments in
            XCTAssertEqual(_target, .workspace(workspacePath))
            XCTAssertEqual(_arguments, buildArguments)

            if _scheme == "A" {
                XCTAssertEqual(_scheme, "A")
                XCTAssertTrue(_clean)
            } else {
                XCTFail("unexpected scheme \(_scheme)")
            }
            return Observable.just(.standardOutput(.init(raw: "success")))
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
        buildgraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildgraphInspector.buildableSchemesStub = { _ in
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

    func test_run_copiesBuildProducts_to_outputPath() throws {
        // Given
        let path = try temporaryPath()
        let buildOutputPath = path.appending(component: ".build")
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = ValueGraph.test()
        let schemeA = Scheme.test(name: "A")

        generator.loadStub = { _ in graph }
        buildgraphInspector.workspacePathStub = { _ in workspacePath }
        buildgraphInspector.buildableSchemesStub = { _ in [schemeA] }
        xcodeBuildController.buildStub = { _, _, _, _ in Observable.just(.standardOutput(.init(raw: "success"))) }

        let xcodeBuildPath = path.appending(components: "Xcode", "DerivedData", "MyProject-hash", "Debug")
        xcodeProjectBuildDirectoryLocator.locateStub = { _, _, _ in xcodeBuildPath }
        try createFiles([
            "Xcode/DerivedData/MyProject-hash/debug/App.app",
            "Xcode/DerivedData/MyProject-hash/debug/App.swiftmodule",
        ])

        // When
        try subject.testRun(schemeName: "A", buildOutputPath: buildOutputPath, path: path)

        // Then
        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(buildOutputPath).sorted(),
            [buildOutputPath.appending(component: "Debug")]
        )

        XCTAssertEqual(
            try fileHandler.contentsOfDirectory(buildOutputPath.appending(component: "Debug")).sorted(),
            [
                buildOutputPath.appending(components: "Debug", "App.app"),
                buildOutputPath.appending(components: "Debug", "App.swiftmodule"),
            ]
        )
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
