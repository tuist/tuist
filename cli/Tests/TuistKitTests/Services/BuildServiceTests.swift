import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TSCUtility
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistKit
@testable import TuistTesting

struct BuildServiceErrorTests {
    @Test func description() {
        #expect(
            BuildServiceError.schemeNotFound(scheme: "A", existing: ["B", "C"]).localizedDescription
                == "Couldn't find scheme A. The available schemes are: B, C."
        )
        #expect(
            BuildServiceError.schemeWithoutBuildableTargets(scheme: "MyScheme").localizedDescription
                == "The scheme MyScheme cannot be built because it contains no buildable targets."
        )
        #expect(
            BuildServiceError.workspaceNotFound(path: "/path/to/workspace").localizedDescription
                == "Workspace not found expected xcworkspace at /path/to/workspace"
        )
    }
}

struct BuildServiceTests {
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var targetBuilder: MockTargetBuilder!
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var subject: BuildService!
    private let fileSystem = FileSystem()
    private let configLoader: MockConfigLoading!

    init() {
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
        configLoader = .init()
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
            targetBuilder: targetBuilder,
            configLoader: configLoader
        )
    }

    @Test func throws_an_error_if_the_project_is_not_generated() async throws {
        // Given
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let scheme = Scheme.test()
            given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(
                .test(project: .testXcodeProject())
            )

            // When/Then
            await #expect(
                throws:
                TuistConfigError
                    .notAGeneratedProjectNorSwiftPackage(
                        errorMessageOverride:
                        "The 'tuist build' command is for generated projects or Swift packages. Please use 'tuist xcodebuild build' instead."
                    ),
                performing: {
                    try await subject.testRun(
                        schemeName: scheme.name,
                        path: temporaryDirectory
                    )
                }
            )
        }
    }

    @Test func run_when_the_project_should_be_generated() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            let graph = Graph.test()
            let scheme = Scheme.test()
            let project = Project.test()
            let target = Target.test()
            let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
            let skipSigning = false

            given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(
                .test(project: .testGeneratedProject())
            )
            given(generator)
                .load(path: .value(temporaryDirectory), options: .any)
                .willReturn(graph)
            given(buildGraphInspector)
                .buildableSchemes(graphTraverser: .any)
                .willReturn([scheme])
            given(buildGraphInspector)
                .buildableTarget(scheme: .value(scheme), graphTraverser: .any)
                .willReturn(GraphTarget.test(path: project.path, target: target, project: project))
            given(buildGraphInspector)
                .workspacePath(directory: .value(temporaryDirectory))
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
                .buildTargetStub = {
                    _, _workspacePath, _scheme, _clean, _, _, _, _device, _osVersion, _, _, _ in
                    XCTAssertEqual(_workspacePath, workspacePath)
                    XCTAssertEqual(_scheme, scheme)
                    XCTAssertTrue(_clean)
                    XCTAssertNil(_device)
                    XCTAssertNil(_osVersion)
                }

            // Then
            try await subject.testRun(
                schemeName: scheme.name,
                path: temporaryDirectory
            )
        }
    }

    @Test func run_when_the_project_is_already_generated() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            let graph = Graph.test()
            let scheme = Scheme.test()
            let project = Project.test()
            let target = Target.test()
            let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
            let skipSigning = false

            given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(
                .test(project: .testGeneratedProject())
            )
            given(generator)
                .load(path: .value(temporaryDirectory), options: .any)
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
                .workspacePath(directory: .value(temporaryDirectory))
                .willReturn(workspacePath)
            given(buildGraphInspector)
                .buildArguments(
                    project: .value(project),
                    target: .value(target),
                    configuration: .any,
                    skipSigning: .value(skipSigning)
                )
                .willReturn(buildArguments)
            targetBuilder.buildTargetStub = {
                _, _workspacePath, _scheme, _clean, _, _, _, _, _, _, _, _ in
                XCTAssertEqual(_workspacePath, workspacePath)
                XCTAssertEqual(_scheme, scheme)
                XCTAssertTrue(_clean)
            }

            // Then
            try await subject.testRun(
                schemeName: scheme.name,
                path: temporaryDirectory
            )
        }
    }

    @Test func run_only_cleans_the_first_time() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            let graph = Graph.test()
            let project = Project.test()
            let schemeA = Scheme.test(name: "A")
            let schemeB = Scheme.test(name: "B")
            let targetA = Target.test(name: "A")
            let targetB = Target.test(name: "B")
            let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
            let skipSigning = false

            given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(
                .test(project: .testGeneratedProject())
            )
            given(generator)
                .load(path: .value(temporaryDirectory), options: .any)
                .willReturn(graph)
            given(buildGraphInspector)
                .buildableSchemes(graphTraverser: .any)
                .willReturn([schemeA, schemeB])
            given(buildGraphInspector)
                .buildableTarget(
                    scheme: .matching {
                        $0 == schemeA || $0 == schemeB
                    }, graphTraverser: .any
                )
                .willProduce { scheme, _ in
                    if scheme == schemeA {
                        return GraphTarget.test(
                            path: project.path, target: targetA, project: project
                        )
                    } else {
                        return GraphTarget.test(
                            path: project.path, target: targetB, project: project
                        )
                    }
                }
            given(buildGraphInspector)
                .workspacePath(directory: .value(temporaryDirectory))
                .willReturn(workspacePath)
            given(buildGraphInspector)
                .buildArguments(
                    project: .any, target: .any, configuration: .any,
                    skipSigning: .value(skipSigning)
                )
                .willReturn(buildArguments)
            targetBuilder
                .buildTargetStub = {
                    _, _workspacePath, _scheme, _clean, _, _, _, _device, _osVersion, _, _, _ in
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
                path: temporaryDirectory
            )
        }
    }

    @Test func run_only_builds_the_given_scheme_when_passed() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            let graph = Graph.test()
            let project = Project.test()
            let schemeA = Scheme.test(name: "A")
            let schemeB = Scheme.test(name: "B")
            let targetA = Target.test(name: "A")
            let targetB = Target.test(name: "B")
            let buildArguments: [XcodeBuildArgument] = [.sdk("iphoneos")]
            let skipSigning = false

            given(configLoader).loadConfig(path: .value(temporaryDirectory)).willReturn(
                .test(project: .testGeneratedProject())
            )
            given(generator)
                .load(path: .value(temporaryDirectory), options: .any)
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
                .buildableTarget(
                    scheme: .matching {
                        $0 == schemeA || $0 == schemeB
                    }, graphTraverser: .any
                )
                .willProduce { scheme, _ in
                    if scheme == schemeA {
                        return GraphTarget.test(
                            path: project.path, target: targetA, project: project
                        )
                    } else {
                        return GraphTarget.test(
                            path: project.path, target: targetB, project: project
                        )
                    }
                }
            given(buildGraphInspector)
                .workspacePath(directory: .value(temporaryDirectory))
                .willReturn(workspacePath)
            given(buildGraphInspector)
                .buildArguments(
                    project: .any, target: .any, configuration: .any,
                    skipSigning: .value(skipSigning)
                )
                .willReturn(buildArguments)
            targetBuilder.buildTargetStub = {
                _, _workspacePath, _scheme, _clean, _, _, _, _, _, _, _, _ in
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
                path: temporaryDirectory
            )
        }
    }

    @Test(.withMockedNoora, .withMockedLogger(), .inTemporaryDirectory) func run_lists_schemes() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
        let graph = Graph.test()
        let schemeA = Scheme.test(name: "A")
        let schemeB = Scheme.test(name: "B")

        given(configLoader).loadConfig(path: .value(temporaryDirectory))
            .willReturn(.test(project: .testGeneratedProject()))
        given(generator)
            .load(path: .value(temporaryDirectory), options: .any)
            .willReturn(graph)
        given(buildGraphInspector)
            .workspacePath(directory: .value(temporaryDirectory))
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
            path: temporaryDirectory
        )
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
