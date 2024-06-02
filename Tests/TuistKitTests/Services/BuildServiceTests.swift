import Foundation
import MockableTest
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistServer
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
    private var generator: MockGenerator!
    private var generatorFactory: MockGeneratorFactorying!
    private var buildGraphInspector: MockBuildGraphInspector!
    private var targetBuilder: MockTargetBuilder!
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var subject: BuildService!

    override func setUp() {
        super.setUp()
        generator = MockGenerator()
        generatorFactory = .init()
        given(generatorFactory)
            .building(
                config: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                cacheStorage: .any
            )
            .willReturn(generator)
        buildGraphInspector = MockBuildGraphInspector()
        targetBuilder = MockTargetBuilder()
        cacheStorageFactory = .init()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(MockCacheStoring())
        subject = BuildService(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            buildGraphInspector: buildGraphInspector,
            targetBuilder: targetBuilder
        )
    }

    override func tearDown() {
        generator = nil
        generatorFactory = nil
        buildGraphInspector = nil
        targetBuilder = nil
        cacheStorageFactory = nil
        subject = nil
        super.tearDown()
    }

    func test_run_when_the_project_should_be_generated() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
        let scheme = Scheme.test()
        let project = Project.test()
        let target = Target.test()
        let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
        let skipSigning = false

        generator.generateWithGraphStub = { _path in
            XCTAssertEqual(_path, path)
            return (path, graph)
        }
        buildGraphInspector.buildableSchemesStub = { _ in
            [scheme]
        }
        buildGraphInspector.buildableTargetStub = { _scheme, _ in
            XCTAssertEqual(_scheme, scheme)
            return GraphTarget.test(path: project.path, target: target, project: project)
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
        targetBuilder
            .buildTargetStub = { _, _workspacePath, _scheme, _clean, _, _, _, _device, _osVersion, _, _, _ in
                XCTAssertEqual(_workspacePath, workspacePath)
                XCTAssertEqual(_scheme, scheme)
                XCTAssertTrue(_clean)
                XCTAssertNil(_device)
                XCTAssertNil(_osVersion)
            }

        // Then
        try await subject.testRun(
            schemeName: scheme.name,
            path: path
        )
    }

    func test_run_when_the_project_is_already_generated() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
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
            return GraphTarget.test(path: project.path, target: target, project: project)
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
        targetBuilder.buildTargetStub = { _, _workspacePath, _scheme, _clean, _, _, _, _, _, _, _, _ in
            XCTAssertEqual(_workspacePath, workspacePath)
            XCTAssertEqual(_scheme, scheme)
            XCTAssertTrue(_clean)
        }

        // Then
        try await subject.testRun(
            schemeName: scheme.name,
            path: path
        )
    }

    func test_run_only_cleans_the_first_time() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
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
            if _scheme == schemeA { return GraphTarget.test(path: project.path, target: targetA, project: project) }
            else if _scheme == schemeB { return GraphTarget.test(path: project.path, target: targetB, project: project) }
            else { XCTFail("unexpected scheme"); return GraphTarget.test(path: project.path, target: targetA, project: project) }
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _, _, _, _skipSigning in
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        targetBuilder
            .buildTargetStub = { _, _workspacePath, _scheme, _clean, _, _, _, _device, _osVersion, _, _, _ in
                XCTAssertEqual(_workspacePath, workspacePath)
                XCTAssertNil(_device)
                XCTAssertNil(_osVersion)

                if _scheme.name == "A" {
                    XCTAssertEqual(_scheme, schemeA)
                    XCTAssertTrue(_clean)
                } else if _scheme.name == "B" {
                    // When running the second scheme clean should be false
                    XCTAssertEqual(_scheme, schemeB)
                    XCTAssertFalse(_clean)
                } else {
                    XCTFail("unexpected scheme \(_scheme.name)")
                }
            }

        // Then
        try await subject.testRun(
            path: path
        )
    }

    func test_run_only_builds_the_given_scheme_when_passed() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
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
            if _scheme == schemeA { return GraphTarget.test(path: project.path, target: targetA, project: project) }
            else if _scheme == schemeB { return GraphTarget.test(path: project.path, target: targetB, project: project) }
            else { XCTFail("unexpected scheme"); return GraphTarget.test(path: project.path, target: targetA, project: project) }
        }
        buildGraphInspector.workspacePathStub = { _path in
            XCTAssertEqual(_path, path)
            return workspacePath
        }
        buildGraphInspector.buildArgumentsStub = { _, _, _, _skipSigning in
            XCTAssertEqual(_skipSigning, skipSigning)
            return buildArguments
        }
        targetBuilder.buildTargetStub = { _, _workspacePath, _scheme, _clean, _, _, _, _, _, _, _, _ in
            XCTAssertEqual(_workspacePath, workspacePath)
            if _scheme.name == "A" {
                XCTAssertEqual(_scheme, schemeA)
                XCTAssertTrue(_clean)
            } else {
                XCTFail("unexpected scheme \(_scheme.name)")
            }
        }

        // Then
        try await subject.testRun(
            schemeName: "A",
            path: path
        )
    }

    func test_run_lists_schemes() async throws {
        // Given
        let path = try temporaryPath()
        let workspacePath = path.appending(component: "App.xcworkspace")
        let graph = Graph.test()
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
        try await subject.testRun(
            path: path
        )

        // Then
        XCTAssertPrinterContains("Found the following buildable schemes: A, B", at: .debug, ==)
    }
}

// MARK: - Helpers

extension BuildService {
    fileprivate func testRun(
        schemeName: String? = nil,
        generate: Bool = false,
        clean: Bool = true,
        configuration: String? = nil,
        ignoreBinaryCache: Bool = false,
        buildOutputPath: AbsolutePath? = nil,
        derivedDataPath: String? = nil,
        path: AbsolutePath,
        device: String? = nil,
        platform: TuistGraph.Platform? = nil,
        osVersion: String? = nil,
        rosetta: Bool = false,
        generateOnly: Bool = false,
        passthroughXcodeBuildArguments: [String] = []
    ) async throws {
        try await run(
            schemeName: schemeName,
            generate: generate,
            clean: clean,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache,
            buildOutputPath: buildOutputPath,
            derivedDataPath: derivedDataPath,
            path: path,
            device: device,
            platform: platform,
            osVersion: osVersion,
            rosetta: rosetta,
            generateOnly: generateOnly,
            passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
        )
    }
}
