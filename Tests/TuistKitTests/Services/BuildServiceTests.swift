import Foundation
import MockableTest
import Path
import TSCUtility
import TuistAutomation
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph
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
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var targetBuilder: MockTargetBuilder!
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var subject: BuildService!

    override func setUp() {
        super.setUp()
        generator = .init()
        generatorFactory = .init()
        given(generatorFactory)
            .building(
                config: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                cacheStorage: .any
            )
            .willReturn(generator)
        buildGraphInspector = .init()
        given(buildGraphInspector)
            .buildableEntrySchemes(graphTraverser: .any)
            .willReturn([])

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

        given(generator)
            .load(path: .value(path))
            .willReturn(graph)
        given(buildGraphInspector)
            .buildableSchemes(graphTraverser: .any)
            .willReturn([scheme])
        given(buildGraphInspector)
            .buildableTarget(scheme: .value(scheme), graphTraverser: .any)
            .willReturn(GraphTarget.test(path: project.path, target: target, project: project))
        given(buildGraphInspector)
            .workspacePath(directory: .value(path))
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .buildArguments(
                project: .value(project),
                target: .value(target),
                configuration: .any,
                skipSigning: .value(skipSigning)
            )
            .willReturn(buildArguments)
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

        given(generator)
            .load(path: .value(path))
            .willReturn(graph)
        given(buildGraphInspector)
            .buildableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    scheme,
                ]
            )
        given(buildGraphInspector)
            .buildableTarget(scheme: .value(scheme), graphTraverser: .any)
            .willReturn(GraphTarget.test(path: project.path, target: target, project: project))
        given(buildGraphInspector)
            .workspacePath(directory: .value(path))
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .buildArguments(
                project: .value(project),
                target: .value(target),
                configuration: .any,
                skipSigning: .value(skipSigning)
            )
            .willReturn(buildArguments)
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

        given(generator)
            .load(path: .value(path))
            .willReturn(graph)
        given(buildGraphInspector)
            .buildableSchemes(graphTraverser: .any)
            .willReturn([schemeA, schemeB])
        given(buildGraphInspector)
            .buildableTarget(scheme: .matching {
                $0 == schemeA || $0 == schemeB
            }, graphTraverser: .any)
            .willProduce { scheme, _ in
                if scheme == schemeA {
                    return GraphTarget.test(path: project.path, target: targetA, project: project)
                } else {
                    return GraphTarget.test(path: project.path, target: targetB, project: project)
                }
            }
        given(buildGraphInspector)
            .workspacePath(directory: .value(path))
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .value(skipSigning))
            .willReturn(buildArguments)
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

        given(generator)
            .load(path: .value(path))
            .willReturn(graph)
        given(buildGraphInspector)
            .buildableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    schemeA,
                    schemeB,
                ]
            )
        given(buildGraphInspector)
            .buildableTarget(scheme: .matching {
                $0 == schemeA || $0 == schemeB
            }, graphTraverser: .any)
            .willProduce { scheme, _ in
                if scheme == schemeA {
                    return GraphTarget.test(path: project.path, target: targetA, project: project)
                } else {
                    return GraphTarget.test(path: project.path, target: targetB, project: project)
                }
            }
        given(buildGraphInspector)
            .workspacePath(directory: .value(path))
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .value(skipSigning))
            .willReturn(buildArguments)
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
        given(generator)
            .load(path: .value(path))
            .willReturn(graph)
        given(buildGraphInspector)
            .workspacePath(directory: .value(path))
            .willReturn(workspacePath)
        given(buildGraphInspector)
            .buildableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    schemeA,
                    schemeB,
                ]
            )

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
        platform: XcodeGraph.Platform? = nil,
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
