import Foundation
import MockableTest
import Path
import TuistAutomation
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class TestServiceTests: TuistUnitTestCase {
    private var subject: TestService!
    private var generator: MockGenerating!
    private var generatorFactory: MockGeneratorFactorying!
    private var xcodebuildController: MockXcodeBuildControlling!
    private var buildGraphInspector: MockBuildGraphInspecting!
    private var simulatorController: MockSimulatorControlling!
    private var contentHasher: MockContentHashing!
    private var testsCacheTemporaryDirectory: TemporaryDirectory!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var configLoader: MockConfigLoading!
    private var cacheStorage: MockCacheStoring!

    override func setUpWithError() throws {
        try super.setUpWithError()
        generator = .init()
        xcodebuildController = .init()
        buildGraphInspector = .init()
        simulatorController = .init()
        contentHasher = .init()
        testsCacheTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        generatorFactory = .init()

        cacheStorage = .init()

        let cacheStorageFactory = MockCacheStorageFactorying()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(cacheStorage)

        given(cacheStorage)
            .store(.any, cacheCategory: .any)
            .willReturn()

        let mockCacheDirectoriesProvider = MockCacheDirectoriesProviding()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider
        let cacheDirectoryProviderFactory = MockCacheDirectoriesProviderFactoring()
        given(cacheDirectoryProviderFactory)
            .cacheDirectories()
            .willReturn(mockCacheDirectoriesProvider)

        let runsCacheDirectory = try temporaryPath()
        given(mockCacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(runsCacheDirectory)

        configLoader = .init()

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willReturn("hash")

        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])

        subject = TestService(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            xcodebuildController: xcodebuildController,
            buildGraphInspector: buildGraphInspector,
            simulatorController: simulatorController,
            contentHasher: contentHasher,
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            configLoader: configLoader
        )

        given(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(.test())
    }

    override func tearDown() {
        generator = nil
        xcodebuildController = nil
        buildGraphInspector = nil
        simulatorController = nil
        testsCacheTemporaryDirectory = nil
        generatorFactory = nil
        contentHasher = nil
        subject = nil
        super.tearDown()
    }

    func test_validateParameters_noParameters() throws {
        try TestService.validateParameters(testTargets: [], skipTestTargets: [])
    }

    func test_validateParameters_nonConflictingParameters_target() throws {
        try TestService.validateParameters(
            testTargets: [TestIdentifier(string: "test1")],
            skipTestTargets: [TestIdentifier(string: "test1/class1")]
        )
    }

    func test_validateParameters_with_testTargets_and_no_skipTestTargets() throws {
        try TestService.validateParameters(
            testTargets: [TestIdentifier(target: "TestTarget", class: "TestClass")],
            skipTestTargets: []
        )
    }

    func test_validateParameters_nonConflictingParameters_targetClass() throws {
        try TestService.validateParameters(
            testTargets: [TestIdentifier(string: "test1/class1")],
            skipTestTargets: [TestIdentifier(string: "test1/class1/method1")]
        )
    }

    func test_validateParameters_conflictingParameters_target() throws {
        let testTargets = try [TestIdentifier(string: "test1")]
        let skipTestTargets = try [TestIdentifier(string: "test2")]
        let error = TestServiceError.nothingToSkip(skipped: skipTestTargets, included: testTargets)
        XCTAssertThrowsSpecific(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            ),
            error
        )
    }

    func test_validateParameters_conflictingParameters_targetClass() throws {
        let testTargets = try [TestIdentifier(string: "test1/class1")]
        let skipTestTargets = try [TestIdentifier(string: "test1/class2")]
        let error = TestServiceError.nothingToSkip(skipped: skipTestTargets, included: testTargets)
        XCTAssertThrowsSpecific(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            ),
            error
        )
    }

    func test_validateParameters_conflictingParameters_targetClassMethod() throws {
        let testTargets = try [TestIdentifier(string: "test1/class1/method1")]
        let skipTestTargets = try [TestIdentifier(string: "test1/class2/method2")]
        let error = TestServiceError.nothingToSkip(skipped: skipTestTargets, included: testTargets)
        XCTAssertThrowsSpecific(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            ),
            error
        )
    }

    func test_validateParameters_duplicatedParameters_target() throws {
        let testTargets = try [TestIdentifier(string: "test1")]
        let skipTestTargets = try [TestIdentifier(string: "test1")]
        let error = TestServiceError.duplicatedTestTargets(Set(testTargets))
        XCTAssertThrowsSpecific(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            ),
            error
        )
    }

    func test_validateParameters_duplicatedParameters_targetClass() throws {
        let testTargets = try [TestIdentifier(string: "test1/class1")]
        let skipTestTargets = try [TestIdentifier(string: "test1/class1")]
        let error = TestServiceError.duplicatedTestTargets(Set(testTargets))
        XCTAssertThrowsSpecific(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            ),
            error
        )
    }

    func test_validateParameters_duplicatedParameters_targetClassMethod() throws {
        let testTargets = try [TestIdentifier(string: "test1/class1/method1")]
        let skipTestTargets = try [TestIdentifier(string: "test1/class1/method1")]
        let error = TestServiceError.duplicatedTestTargets(Set(testTargets))
        XCTAssertThrowsSpecific(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            ),
            error
        )
    }

    func test_run_generates_project() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        given(generator)
            .generateWithGraph(path: .value(path))
            .willReturn((path, .test(), MapperEnvironment()))
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        // When
        try await subject.testRun(
            path: path
        )
    }

    func test_run_tests_with_specified_arch() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "App-Workspace"),
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willProduce { scheme, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])), MapperEnvironment())
            }
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .value(true),
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willReturn(())

        // When / Then
        try await subject.testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            rosetta: true
        )
    }

    func test_run_tests_for_only_specified_scheme() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "App-Workspace"),
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willProduce { scheme, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])), MapperEnvironment())
            }
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }

        // When
        try await subject.testRun(
            schemeName: "TestScheme",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["TestScheme"])
    }

    func test_run_tests_all_project_schemes() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectSchemeOne"),
                    Scheme.test(name: "ProjectSchemeTwo"),
                ]
            )
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(), MapperEnvironment())
            }
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )

        // When
        try await subject.testRun(
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

    func test_run_tests_individual_scheme() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectSchemeOne"),
                    Scheme.test(name: "ProjectSchemeTwo"),
                ]
            )
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOne"), .test(name: "ProjectSchemeTwo")])),
                    MapperEnvironment()
                )
            }
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["ProjectSchemeOne"])
    }

    func test_run_tests_individual_scheme_with_no_test_actions() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOne", testAction: .test(targets: []))])),
                    MapperEnvironment()
                )
            }
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        XCTAssertStandardOutput(pattern: "The scheme ProjectSchemeOne's test action has no tests to run, finishing early.")
        XCTAssertEmpty(testedSchemes)
    }

    func test_throws_when_scheme_does_not_exist_and_initial_graph_is_nil() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(
                        projects: [
                            try self.temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeTwo")]),
                        ]
                    ),
                    MapperEnvironment()
                )
            }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.testRun(
                schemeName: "ProjectSchemeOne",
                path: try temporaryPath()
            ),
            TestServiceError.schemeNotFound(
                scheme: "ProjectSchemeOne",
                existing: ["ProjectSchemeTwo"]
            )
        )
    }

    func test_throws_scheme_does_not_exist_in_initial_graph() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        var environment = MapperEnvironment()
        environment.initialGraph = .test(
            workspace: .test(
                schemes: [.test(name: "ProjectSchemeTwo", testAction: .test(targets: []))]
            ),
            projects: [
                try temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeTwo")]),
            ]
        )
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(),
                    environment
                )
            }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.testRun(
                schemeName: "ProjectSchemeOne",
                path: try temporaryPath()
            ),
            TestServiceError.schemeNotFound(
                scheme: "ProjectSchemeOne",
                existing: ["ProjectSchemeTwo"]
            )
        )
    }

    func test_skips_running_tests_when_scheme_is_in_initial_graph_only() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }
        var environment = MapperEnvironment()
        environment.initialGraph = .test(
            projects: [
                try temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeOne")]),
            ]
        )
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(),
                    environment
                )
            }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEmpty(testedSchemes)
        XCTAssertStandardOutput(pattern: "The scheme ProjectSchemeOne's test action has no tests to run, finishing early.")
    }

    func test_run_tests_when_part_is_cached() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])

        let projectPathOne = try temporaryPath().appending(component: "ProjectOne")
        let schemeOne = Scheme.test(
            name: "ProjectSchemeOne",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetA")),
                ]
            )
        )
        let schemeTwo = Scheme.test(
            name: "ProjectSchemeTwo",
            testAction: .test(
                targets: []
            )
        )

        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([schemeOne, schemeTwo])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .any,
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any
            )
            .willReturn(.test())
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }
        var environment = MapperEnvironment()
        environment.initialGraph = .test(
            projects: [
                projectPathOne: .test(
                    path: projectPathOne,
                    targets: [
                        .test(name: "TargetA", bundleId: "io.tuist.TargetA"),
                        .test(name: "TargetB", bundleId: "io.tuist.TargetB"),
                        .test(name: "TargetC", bundleId: "io.tuist.TargetC"),
                    ],
                    schemes: [
                        .test(
                            name: "ProjectSchemeOne",
                            testAction: .test(
                                targets: [
                                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetA")),
                                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetB")),
                                ]
                            )
                        ),
                        .test(
                            name: "ProjectSchemeTwo",
                            testAction: .test(
                                targets: [
                                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetC")),
                                ]
                            )
                        ),
                    ]
                ),
            ]
        )
        environment.testsCacheUntestedHashes = [
            .test(name: "TargetA", bundleId: "io.tuist.TargetA"): "hash-a",
        ]
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(
                        projects: [
                            projectPathOne: .test(
                                path: projectPathOne,
                                targets: [
                                    .test(name: "TargetA"),
                                    .test(name: "TargetB"),
                                ],
                                schemes: [schemeOne, schemeTwo]
                            ),
                        ]
                    ),
                    environment
                )
            }

        // When
        try await subject.testRun(
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["ProjectSchemeOne"])
        XCTAssertStandardOutput(
            pattern: "The following targets have not changed since the last successful run and will be skipped: TargetB, TargetC"
        )
        verify(cacheStorage)
            .store(
                .value(
                    [
                        CacheStorableItem(name: "TargetA", hash: "hash-a"): [],
                    ]
                ),
                cacheCategory: .value(.selectiveTests)
            )
            .called(1)
    }

    func test_run_tests_when_part_is_cached_and_scheme_is_passed() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])

        let projectPathOne = try temporaryPath().appending(component: "ProjectOne")
        let schemeOne = Scheme.test(
            name: "ProjectSchemeOne",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetA")),
                ]
            )
        )
        let schemeTwo = Scheme.test(
            name: "ProjectSchemeTwo",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetD")),
                ]
            )
        )

        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([schemeOne, schemeTwo])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .any,
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any
            )
            .willReturn(.test())
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }
        var environment = MapperEnvironment()
        environment.initialGraph = .test(
            projects: [
                projectPathOne: .test(
                    path: projectPathOne,
                    targets: [
                        .test(name: "TargetA", bundleId: "io.tuist.TargetA"),
                        .test(name: "TargetB", bundleId: "io.tuist.TargetB"),
                        .test(name: "TargetC", bundleId: "io.tuist.TargetC"),
                        .test(name: "TargetD", bundleId: "io.tuist.TargetD"),
                    ],
                    schemes: [
                        .test(
                            name: "ProjectSchemeOne",
                            testAction: .test(
                                targets: [
                                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetA")),
                                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetB")),
                                ]
                            )
                        ),
                        .test(
                            name: "ProjectSchemeTwo",
                            testAction: .test(
                                targets: [
                                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetC")),
                                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetD")),
                                ]
                            )
                        ),
                    ]
                ),
            ]
        )
        environment.testsCacheUntestedHashes = [
            .test(name: "TargetA", bundleId: "io.tuist.TargetA"): "hash-a",
            .test(name: "TargetD", bundleId: "io.tuist.TargetD"): "hash-d",
        ]
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(
                        projects: [
                            projectPathOne: .test(
                                path: projectPathOne,
                                targets: [
                                    .test(name: "TargetA"),
                                    .test(name: "TargetB"),
                                    .test(name: "TargetC"),
                                    .test(name: "TargetD"),
                                ],
                                schemes: [schemeOne, schemeTwo]
                            ),
                        ]
                    ),
                    environment
                )
            }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeTwo",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["ProjectSchemeTwo"])
        XCTAssertStandardOutput(
            pattern: "The following targets have not changed since the last successful run and will be skipped: TargetC"
        )
        verify(cacheStorage)
            .store(
                .value(
                    [
                        CacheStorableItem(name: "TargetD", hash: "hash-d"): [],
                    ]
                ),
                cacheCategory: .value(.selectiveTests)
            )
            .called(1)
    }

    func test_run_tests_with_skipped_targets() async throws {
        // Given
        given(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .value([]),
                skipUITests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any
            )
            .willReturn(generator)
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectSchemeOneTests"),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOneTests")])), MapperEnvironment())
            }
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOneTests",
            path: try temporaryPath(),
            skipTestTargets: [.init(target: "ProjectSchemeOneTests", class: "TestClass")]
        )

        // Then
        XCTAssertEqual(testedSchemes, ["ProjectSchemeOneTests"])
    }

    func test_run_tests_all_project_schemes_when_fails() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectScheme"),
                ]
            )
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(), MapperEnvironment())
            }
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
                throw NSError.test()
            }
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )

        // When / Then
        do {
            try await subject.testRun(
                path: try temporaryPath()
            )
            XCTFail("Should throw")
        } catch {}
        XCTAssertEqual(
            testedSchemes,
            [
                "ProjectScheme",
            ]
        )
//        XCTAssertFalse(
//            fileHandler.exists(cacheDirectoriesProvider.cacheDirectory(for: .selectiveTests).appending(component: "A"))
//        )
    }

    func test_run_tests_when_no_project_schemes_present() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(), MapperEnvironment())
            }
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }

        // When
        try await subject.testRun(
            path: try temporaryPath()
        )

        // Then
        XCTAssertEmpty(testedSchemes)
        XCTAssertPrinterOutputContains("There are no tests to run, finishing early")
    }

    func test_run_uses_resource_bundle_path() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        let expectedResourceBundlePath = try AbsolutePath(validating: "/test")
        var resourceBundlePath: AbsolutePath?

        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, _, _, _, _, _, gotResourceBundlePath, _, _, _, _, _, _ in
                resourceBundlePath = gotResourceBundlePath
            }
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(), MapperEnvironment())
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectScheme"),
                ]
            )
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.testRun(
            path: try temporaryPath(),
            resultBundlePath: expectedResourceBundlePath
        )

        // Then
        XCTAssertEqual(
            resourceBundlePath,
            expectedResourceBundlePath
        )
    }

    func test_run_saves_resource_bundle_when_cloud_is_configured() async throws {
        // Given
        givenGenerator()
        var resultBundlePath: AbsolutePath?
        let expectedResultBundlePath = try cacheDirectoriesProvider
            .cacheDirectory(for: .runs)
            .appending(components: "run-id", Constants.resultBundleName)

        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, _, _, _, _, _, gotResourceBundlePath, _, _, _, _, _, _ in
                resultBundlePath = gotResourceBundlePath
            }
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(), MapperEnvironment())
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectScheme"),
                ]
            )
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    fullHandle: "tuist/tuist"
                )
            )

        let runsCacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(runsCacheDirectory)

        try fileHandler.createFolder(runsCacheDirectory)

        // When
        try await subject.testRun(
            runId: "run-id",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(resultBundlePath, expectedResultBundlePath)
    }

    func test_run_uses_resource_bundle_path_with_given_scheme() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        let expectedResourceBundlePath = try AbsolutePath(validating: "/test")
        var resourceBundlePath: AbsolutePath?

        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, _, _, _, _, _, gotResourceBundlePath, _, _, _, _, _, _ in
                resourceBundlePath = gotResourceBundlePath
            }

        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectScheme2")])), MapperEnvironment())
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectScheme"),
                    Scheme.test(name: "ProjectScheme2"),
                ]
            )
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())

        // When
        try await subject.testRun(
            schemeName: "ProjectScheme2",
            path: try temporaryPath(),
            resultBundlePath: expectedResourceBundlePath
        )

        // Then
        XCTAssertEqual(
            resourceBundlePath,
            expectedResourceBundlePath
        )
    }

    func test_run_passes_retry_count_as_argument() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectSchemeOne"),
                ]
            )
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOne")])), MapperEnvironment())
            }
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())

        var passedRetryCount = 0
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, _, _, _, _, _, _, _, retryCount, _, _, _, _ in
                passedRetryCount = retryCount
            }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath(),
            retryCount: 3
        )

        // Then
        XCTAssertEqual(passedRetryCount, 3)
    }

    func test_run_defaults_retry_count_to_zero() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectSchemeOne"),
                ]
            )
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOne")])), MapperEnvironment())
            }
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())

        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willReturn()

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .value(0),
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_test_plan_success() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        let testPlan = "TestPlan"
        let testPlanPath = try AbsolutePath(validating: "/testPlan/\(testPlan)")
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "App-Workspace"),
                    Scheme.test(
                        name: "TestScheme",
                        testAction: .test(
                            testPlans: [.init(path: testPlanPath, testTargets: [], isDefault: true)]
                        )
                    ),
                ]
            )
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .value(testPlan),
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any
            )
            .willProduce { scheme, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (
                    path,
                    .test(
                        workspace: .test(
                            schemes: [
                                .test(
                                    name: "TestScheme",
                                    testAction: .test(targets: [.test()])
                                ),
                            ]
                        )
                    ),
                    MapperEnvironment()
                )
            }
        var testedSchemes: [String] = []
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
                testedSchemes.append(scheme)
            }

        // When
        try await subject.testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            testPlanConfiguration: TestPlanConfiguration(testPlan: testPlan)
        )

        // Then
        XCTAssertEqual(testedSchemes, ["TestScheme"])
    }

    func test_run_test_plan_failure() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        let testPlan = "TestPlan"
        let testPlanPath = try AbsolutePath(validating: "/testPlan/\(testPlan)")
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "App-Workspace"),
                    Scheme.test(
                        name: "TestScheme",
                        testAction: .test(
                            testPlans: [.init(path: testPlanPath, testTargets: [], isDefault: true)]
                        )
                    ),
                ]
            )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectSchemeOne"),
                ]
            )
        given(buildGraphInspector)
            .testableTarget(scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any, graphTraverser: .any)
            .willReturn(.test())
        given(generator)
            .generateWithGraph(path: .any)
            .willProduce { path in
                (path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])), MapperEnvironment())
            }
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willReturn(())

        let notDefinedTestPlan = "NotDefined"
        do {
            // When
            try await subject.testRun(
                schemeName: "TestScheme",
                path: try temporaryPath(),
                testPlanConfiguration: TestPlanConfiguration(testPlan: notDefinedTestPlan)
            )
        } catch let TestServiceError.testPlanNotFound(_, passedTestPlan, existing) {
            // Then
            XCTAssertEqual(passedTestPlan, notDefinedTestPlan)
            XCTAssertEqual(existing, [testPlan])
        } catch {
            throw error
        }
    }

    private func givenGenerator() {
        given(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any
            )
            .willReturn(generator)
    }
}

extension TestService {
    fileprivate func testRun(
        runId: String = "run-id",
        schemeName: String? = nil,
        clean: Bool = false,
        configuration: String? = nil,
        path: AbsolutePath,
        deviceName: String? = nil,
        platform: String? = nil,
        osVersion: String? = nil,
        rosetta: Bool = false,
        skipUiTests: Bool = false,
        resultBundlePath: AbsolutePath? = nil,
        derivedDataPath: String? = nil,
        retryCount: Int = 0,
        testTargets: [TestIdentifier] = [],
        skipTestTargets: [TestIdentifier] = [],
        testPlanConfiguration: TestPlanConfiguration? = nil,
        generateOnly: Bool = false,
        passthroughXcodeBuildArguments: [String] = []
    ) async throws {
        try await run(
            runId: runId,
            schemeName: schemeName,
            clean: clean,
            configuration: configuration,
            path: path,
            deviceName: deviceName,
            platform: platform,
            osVersion: osVersion,
            rosetta: rosetta,
            skipUITests: skipUiTests,
            resultBundlePath: resultBundlePath,
            derivedDataPath: derivedDataPath,
            retryCount: retryCount,
            testTargets: testTargets,
            skipTestTargets: skipTestTargets,
            testPlanConfiguration: testPlanConfiguration,
            ignoreBinaryCache: false,
            ignoreSelectiveTesting: false,
            generateOnly: generateOnly,
            passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
        )
    }
}
