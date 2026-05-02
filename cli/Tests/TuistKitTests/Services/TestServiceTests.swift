import Foundation
import Mockable
import Path
import TuistAlert
import TuistAutomation
import TuistCache
import TuistCI
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistGenerator
import TuistGit
import TuistLoader
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXcodeBuildProducts
import TuistXCResultService
import XcodeGraph
import XCResultParser
import XCTest

@testable import TuistKit
@testable import TuistTesting

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
    private var cacheStorageFactory: MockCacheStorageFactorying!
    private var cacheStorage: MockCacheStoring!
    private var runMetadataStorage: RunMetadataStorage!
    private var testedSchemes: [String] = []
    private var xcResultService: MockXCResultServicing!
    private var xcodeBuildArgumentParser: MockXcodeBuildArgumentParsing!
    private var uploadResultBundleService: MockUploadResultBundleServicing!
    private var derivedDataLocator: MockDerivedDataLocating!
    private var createTestService: MockCreateTestServicing!
    private var gitController: MockGitControlling!
    private var ciController: MockCIControlling!
    private var testQuarantineService: MockTestQuarantineServicing!
    private var testCaseListService: MockTestCaseListServicing!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var shardPlanService: MockShardPlanServicing!
    private var shardMatrixOutputService: MockShardMatrixOutputServicing!
    private var shardService: MockShardServicing!
    private var xcActivityLogController: MockXCActivityLogControlling!
    private var uploadBuildRunService: MockUploadBuildRunServicing!

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
        runMetadataStorage = RunMetadataStorage()
        xcResultService = .init()
        xcodeBuildArgumentParser = MockXcodeBuildArgumentParsing()
        uploadResultBundleService = .init()
        derivedDataLocator = .init()
        createTestService = .init()
        gitController = .init()
        ciController = .init()
        testQuarantineService = .init()
        testCaseListService = .init()
        serverEnvironmentService = .init()
        shardPlanService = .init()
        shardMatrixOutputService = .init()
        shardService = .init()
        xcActivityLogController = .init()
        uploadBuildRunService = .init()

        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
            .willReturn(nil)

        cacheStorageFactory = MockCacheStorageFactorying()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(cacheStorage)

        given(cacheStorage)
            .store(.any, cacheCategory: .any)
            .willReturn([])

        cacheDirectoriesProvider = MockCacheDirectoriesProviding()

        let runsCacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(runsCacheDirectory)

        configLoader = .init()

        given(contentHasher)
            .hash(Parameter<String>.any)
            .willReturn("hash")

        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])

        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(
                .test(destination: nil)
            )

        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(try temporaryPath().appending(component: "DerivedData"))

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(try temporaryPath())

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        given(ciController)
            .ciInfo()
            .willReturn(nil)

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(URL(string: "https://tuist.dev")!)

        given(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .any)
            .willReturn([])
        given(testQuarantineService)
            .markQuarantinedTests(testSummary: .any, quarantinedTests: .any)
            .willProduce { summary, _ in summary }
        given(testQuarantineService)
            .onlyQuarantinedTestsFailed(testSummary: .any)
            .willReturn(false)
        given(testQuarantineService)
            .onlyQuarantinedTestsFailed(testStatuses: .any, quarantinedTests: .any)
            .willReturn(false)
        given(shardMatrixOutputService)
            .output(.any)
            .willReturn()

        given(uploadResultBundleService)
            .uploadTestSummary(
                testSummary: .any,
                projectDerivedDataDirectory: .any,
                config: .any,
                shardPlanId: .any,
                shardIndex: .any
            )
            .willReturn(
                Components.Schemas.RunsTest(
                    duration: 0,
                    id: "stub",
                    project_id: 0,
                    test_case_runs: [],
                    _type: .test,
                    url: ""
                )
            )

        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willReturn(nil)
        given(xcResultService)
            .parseTestStatuses(path: .any)
            .willReturn(TestResultStatuses(testCases: []))

        subject = TestService(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            xcodebuildController: xcodebuildController,
            buildGraphInspector: buildGraphInspector,
            simulatorController: simulatorController,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            configLoader: configLoader,
            xcResultService: xcResultService,
            gitController: gitController,
            uploadResultBundleService: uploadResultBundleService,
            derivedDataLocator: derivedDataLocator,
            createTestService: createTestService,
            serverEnvironmentService: serverEnvironmentService,
            ciController: ciController,
            testQuarantineService: testQuarantineService,
            testCaseListService: testCaseListService,
            shardPlanService: shardPlanService,
            shardMatrixOutputService: shardMatrixOutputService,
            shardService: shardService,
            xcActivityLogController: xcActivityLogController,
            uploadBuildRunService: uploadBuildRunService
        )

        given(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(.test())

        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])

        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _, _ in
                self.testedSchemes.append(scheme)
            }
    }

    override func tearDown() {
        generator = nil
        xcodebuildController = nil
        buildGraphInspector = nil
        simulatorController = nil
        testsCacheTemporaryDirectory = nil
        generatorFactory = nil
        contentHasher = nil
        cacheStorageFactory = nil
        cacheStorage = nil
        testedSchemes = []
        runMetadataStorage = nil
        uploadResultBundleService = nil
        derivedDataLocator = nil
        createTestService = nil
        gitController = nil
        ciController = nil
        testQuarantineService = nil
        serverEnvironmentService = nil
        shardPlanService = nil
        shardService = nil
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

    func test_validateParameters_conflictingParameters_target_doesNotThrow() throws {
        let testTargets = try [TestIdentifier(string: "test1")]
        let skipTestTargets = try [TestIdentifier(string: "test2")]
        XCTAssertNoThrow(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            )
        )
    }

    func test_validateParameters_conflictingParameters_targetClass_doesNotThrow() throws {
        let testTargets = try [TestIdentifier(string: "test1/class1")]
        let skipTestTargets = try [TestIdentifier(string: "test1/class2")]
        XCTAssertNoThrow(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            )
        )
    }

    func test_validateParameters_conflictingParameters_targetClassMethod_doesNotThrow() throws {
        let testTargets = try [TestIdentifier(string: "test1/class1/method1")]
        let skipTestTargets = try [TestIdentifier(string: "test1/class2/method2")]
        XCTAssertNoThrow(
            try TestService.validateParameters(
                testTargets: testTargets,
                skipTestTargets: skipTestTargets
            )
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

    func test_throws_when_shard_planning_flags_are_passed_without_build_only() async throws {
        await XCTAssertThrowsSpecific(
            {
                try await testRun(
                    path: try temporaryPath(),
                    action: .test,
                    shardTotal: 5
                )
            },
            TestServiceError.shardPlanningRequiresBuildOnly
        )
    }

    func test_throws_when_shard_index_is_passed_without_without_building() async throws {
        await XCTAssertThrowsSpecific(
            {
                try await testRun(
                    path: try temporaryPath(),
                    action: .test,
                    shardIndex: 0
                )
            },
            TestServiceError.shardIndexRequiresWithoutBuilding
        )
    }

    func test_throws_an_error_when_config_is_not_for_generated_project() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testXcodeProject()))
        given(generator)
            .generateWithGraph(path: .value(path), options: .any)
            .willReturn((path, .test(), MapperEnvironment()))

        // When
        await XCTAssertThrowsSpecific(
            {
                try await testRun(
                    path: path
                )
            },
            TuistConfigError
                .notAGeneratedProjectNorSwiftPackage(
                    errorMessageOverride:
                    "The 'tuist test' command is for generated projects or Swift packages. Please use 'tuist xcodebuild test' instead."
                )
        )
    }

    func test_run_generates_project() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        given(generator)
            .generateWithGraph(path: .value(path), options: .any)
            .willReturn((path, .test(), MapperEnvironment()))
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            path: path
        )
    }

    func test_run_tests_with_specified_arch() async throws {
        // Given
        givenGenerator()
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "App-Workspace"),
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willProduce { scheme, _, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])),
                    MapperEnvironment()
                )
            }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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
        try await testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            rosetta: true
        )
    }

    func test_run_tests_with_passthrough_destination() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])),
                    MapperEnvironment()
                )
            }
        given(simulatorController)
            .findAvailableDevice(udid: .any)
            .willReturn(.test(device: .test(name: "Test iPhone")))

        // When
        try await testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            passthroughXcodeBuildArguments: ["-destination", "id=device-id"]
        )

        // Then
        verify(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .called(0)
        verify(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .value(.test(device: .test(name: "Test iPhone"))),
                schemeName: .any
            )
            .called(1)
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .value(nil),
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .value(["-destination", "id=device-id"])
            )
            .called(1)
    }

    func test_run_tests_for_only_specified_scheme() async throws {
        // Given
        givenGenerator()
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "App-Workspace"),
                    Scheme.test(name: "TestScheme"),
                ]
            )
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willProduce { scheme, _, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])),
                    MapperEnvironment()
                )
            }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            schemeName: "TestScheme",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["TestScheme"])
    }

    func test_run_tests_all_project_schemes() async throws {
        // Given
        givenGenerator()
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
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, .test(), MapperEnvironment())
            }
        try await fileSystem.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try await fileSystem.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
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

    func test_run_uploads_to_local_cache_storage_when_no_upload() async throws {
        // Given
        givenGenerator()

        let projectPathOne = try temporaryPath().appending(component: "ProjectOne")
        let schemeOne = Scheme.test(
            name: "ProjectSchemeOne",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPathOne, name: "TargetA")),
                ]
            )
        )

        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([schemeOne])

        var environment = MapperEnvironment()
        environment.initialGraph = .test(
            projects: [
                projectPathOne: .test(
                    path: projectPathOne,
                    targets: [
                        .test(name: "TargetA", bundleId: "dev.tuist.TargetA"),
                    ],
                    schemes: [
                        .test(
                            name: "ProjectSchemeOne",
                            testAction: .test(
                                targets: [
                                    .test(
                                        target: TargetReference(
                                            projectPath: projectPathOne, name: "TargetA"
                                        )
                                    ),
                                ]
                            )
                        ),
                    ]
                ),
            ]
        )
        environment.targetTestHashes = [
            projectPathOne: [
                "TargetA": "hash-a",
            ],
        ]
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(
                        projects: [
                            projectPathOne: .test(
                                path: projectPathOne,
                                targets: [
                                    .test(name: "TargetA"),
                                ],
                                schemes: [schemeOne]
                            ),
                        ]
                    ),
                    environment
                )
            }
        let localCacheStorage = MockCacheStoring()
        given(cacheStorageFactory)
            .cacheLocalStorage()
            .willReturn(localCacheStorage)
        given(localCacheStorage)
            .store(.any, cacheCategory: .any)
            .willReturn([])
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            noUpload: true,
            path: try temporaryPath()
        )

        // Then
        verify(localCacheStorage)
            .store(.any, cacheCategory: .any)
            .called(1)

        verify(cacheStorage)
            .store(.any, cacheCategory: .any)
            .called(0)
    }

    func test_run_uploads_build_run_using_passthrough_derived_data_path() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let projectPath = path.appending(component: "Project")
        let passthroughDerivedDataPath = path.appending(component: "passthrough-derived-data")
        let activityLogPath = passthroughDerivedDataPath.appending(
            components: "Logs", "Build", "activity.xcactivitylog"
        )
        let scheme = Scheme.test(
            name: "AppTests",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPath, name: "AppTests")),
                ]
            )
        )

        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([scheme])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test(target: .test(name: "AppTests")))

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(
                        workspace: .test(schemes: [scheme]),
                        projects: [
                            projectPath: .test(
                                path: projectPath,
                                targets: [.test(name: "AppTests")],
                                schemes: [scheme]
                            ),
                        ]
                    ),
                    MapperEnvironment()
                )
            }

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    project: .testGeneratedProject(),
                    fullHandle: "tuist/tuist",
                    url: URL(string: "https://example.com")!
                )
            )

        xcodeBuildArgumentParser.reset()
        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(derivedDataPath: passthroughDerivedDataPath))

        var mostRecentActivityLogProjectDirectory: AbsolutePath?
        xcActivityLogController.reset()
        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
            .willProduce { directory, _ in
                mostRecentActivityLogProjectDirectory = directory
                return .test(path: activityLogPath)
            }

        given(uploadBuildRunService)
            .uploadBuildRun(
                activityLogPath: .any,
                projectPath: .any,
                config: .any,
                scheme: .any,
                configuration: .any
            )
            .willReturn(URL(string: "https://tuist.dev/test")!)

        // When
        try await testRun(
            path: path,
            passthroughXcodeBuildArguments: ["-derivedDataPath", passthroughDerivedDataPath.pathString]
        )

        // Then — derivedDataLocator must NOT have been used; the passthrough path is honored.
        XCTAssertEqual(mostRecentActivityLogProjectDirectory, passthroughDerivedDataPath)
        verify(derivedDataLocator)
            .locate(for: .any)
            .called(0)

        verify(uploadBuildRunService)
            .uploadBuildRun(
                activityLogPath: .value(activityLogPath),
                projectPath: .any,
                config: .any,
                scheme: .any,
                configuration: .any
            )
            .called(1)
    }

    func test_run_tests_individual_scheme() async throws {
        // Given
        givenGenerator()
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
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(
                        workspace: .test(schemes: [
                            .test(name: "ProjectSchemeOne"), .test(name: "ProjectSchemeTwo"),
                        ])
                    ),
                    MapperEnvironment()
                )
            }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        try await fileSystem.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try await fileSystem.touch(
            testsCacheTemporaryDirectory.path.appending(component: "B")
        )

        // When
        try await testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(testedSchemes, ["ProjectSchemeOne"])
    }

    func test_run_tests_individual_scheme_with_no_test_actions() async throws {
        // Given
        try await withMockedDependencies {
            givenGenerator()
            given(buildGraphInspector)
                .testableSchemes(graphTraverser: .any)
                .willReturn([])
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (
                        path,
                        .test(
                            workspace: .test(schemes: [
                                .test(name: "ProjectSchemeOne", testAction: .test(targets: [])),
                            ])
                        ),
                        MapperEnvironment()
                    )
                }
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            try await fileSystem.touch(
                testsCacheTemporaryDirectory.path.appending(component: "A")
            )
            try await fileSystem.touch(
                testsCacheTemporaryDirectory.path.appending(component: "B")
            )

            // When
            try await testRun(
                schemeName: "ProjectSchemeOne",
                path: try temporaryPath()
            )

            // Then
            XCTAssertStandardOutput(
                pattern:
                "The scheme ProjectSchemeOne's test action has no tests to run, finishing early."
            )
            XCTAssertEmpty(testedSchemes)
        }
    }

    func test_throws_when_scheme_does_not_exist_and_initial_graph_is_nil() async throws {
        // Given
        givenGenerator()
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(
                        projects: [
                            try self.temporaryPath(): .test(schemes: [
                                .test(name: "ProjectSchemeTwo"),
                            ]),
                        ]
                    ),
                    MapperEnvironment()
                )
            }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When / Then
        await XCTAssertThrowsSpecific(
            try await testRun(
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
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(),
                    environment
                )
            }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await testRun(
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
        try await withMockedDependencies {
            // Given
            givenGenerator()
            var environment = MapperEnvironment()
            environment.initialGraph = .test(
                projects: [
                    try temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeOne")]),
                ]
            )
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (
                        path,
                        .test(),
                        environment
                    )
                }

            // When
            try await testRun(
                schemeName: "ProjectSchemeOne",
                path: try temporaryPath()
            )

            // Then
            XCTAssertEmpty(testedSchemes)
            XCTAssertStandardOutput(
                pattern:
                "The scheme ProjectSchemeOne's test action has no tests to run, finishing early."
            )
        }
    }

    func test_skips_running_tests_when_all_tests_are_cached() async throws {
        try await withMockedDependencies {
            // Given
            givenGenerator()
            var environment = MapperEnvironment()
            environment.initialGraph = .test(
                projects: [
                    try temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeOne")]),
                ]
            )
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (
                        path,
                        .test(),
                        environment
                    )
                }

            // When
            try await testRun(
                path: try temporaryPath()
            )

            // Then
            XCTAssertEmpty(testedSchemes)
            XCTAssertStandardOutput(pattern: "There are no tests to run, finishing early")
        }
    }

    func test_writes_empty_shard_matrix_when_all_tests_are_cached_and_sharding_is_enabled() async throws {
        try await withMockedDependencies {
            // Given
            givenGenerator()
            var environment = MapperEnvironment()
            environment.initialGraph = .test(
                projects: [
                    try temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeOne")]),
                ]
            )
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (
                        path,
                        .test(),
                        environment
                    )
                }
            given(shardMatrixOutputService)
                .output(.any)
                .willReturn()

            // When
            try await testRun(
                path: try temporaryPath(),
                action: .build,
                shardTotal: 2
            )

            // Then
            XCTAssertEmpty(testedSchemes)
            verify(shardMatrixOutputService)
                .output(.any)
                .called(1)
        }
    }

    func test_writes_empty_shard_matrix_when_scheme_is_in_initial_graph_only_and_sharding_is_enabled() async throws {
        try await withMockedDependencies {
            // Given
            givenGenerator()
            var environment = MapperEnvironment()
            environment.initialGraph = .test(
                projects: [
                    try temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeOne")]),
                ]
            )
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (
                        path,
                        .test(),
                        environment
                    )
                }
            given(shardMatrixOutputService)
                .output(.any)
                .willReturn()

            // When
            try await testRun(
                schemeName: "ProjectSchemeOne",
                path: try temporaryPath(),
                action: .build,
                shardTotal: 2
            )

            // Then
            XCTAssertEmpty(testedSchemes)
            verify(shardMatrixOutputService)
                .output(.any)
                .called(1)
        }
    }

    func test_writes_empty_shard_matrix_when_scheme_has_no_test_targets_and_sharding_is_enabled() async throws {
        try await withMockedDependencies {
            // Given
            givenGenerator()
            given(buildGraphInspector)
                .testableSchemes(graphTraverser: .any)
                .willReturn([])
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (
                        path,
                        .test(
                            workspace: .test(schemes: [
                                .test(name: "ProjectSchemeOne", testAction: .test(targets: [])),
                            ])
                        ),
                        MapperEnvironment()
                    )
                }
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            given(shardMatrixOutputService)
                .output(.any)
                .willReturn()

            // When
            try await testRun(
                schemeName: "ProjectSchemeOne",
                path: try temporaryPath(),
                action: .build,
                shardTotal: 2
            )

            // Then
            XCTAssertEmpty(testedSchemes)
            verify(shardMatrixOutputService)
                .output(.any)
                .called(1)
        }
    }

    func test_skips_running_tests_when_all_tests_are_cached_with_a_custom_result_bundle_path()
        async throws
    {
        try await withMockedDependencies {
            // Given
            givenGenerator()
            var environment = MapperEnvironment()
            environment.initialGraph = .test(
                projects: [
                    try temporaryPath(): .test(schemes: [.test(name: "ProjectSchemeOne")]),
                ]
            )
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (
                        path,
                        .test(),
                        environment
                    )
                }

            let resultBundlePath = try temporaryPath()
                .appending(component: "test.xcresult")

            // When
            try await testRun(
                path: try temporaryPath(),
                resultBundlePath: resultBundlePath
            )

            // Then
            XCTAssertEmpty(testedSchemes)
            XCTAssertStandardOutput(pattern: "There are no tests to run, finishing early")
        }
    }

    func test_run_tests_when_part_is_cached() async throws {
        try await withMockedDependencies {
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
                    graphTraverser: .any,
                    action: .any
                )
                .willReturn(.test())

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
                                        .test(
                                            target: TargetReference(
                                                projectPath: projectPathOne, name: "TargetA"
                                            )
                                        ),
                                        .test(
                                            target: TargetReference(
                                                projectPath: projectPathOne, name: "TargetB"
                                            )
                                        ),
                                    ]
                                )
                            ),
                            .test(
                                name: "ProjectSchemeTwo",
                                testAction: .test(
                                    targets: [
                                        .test(
                                            target: TargetReference(
                                                projectPath: projectPathOne, name: "TargetC"
                                            )
                                        ),
                                    ]
                                )
                            ),
                        ]
                    ),
                ]
            )
            environment.targetTestHashes = [
                projectPathOne: [
                    "TargetA": "hash-a",
                    "TargetB": "hash-b",
                    "TargetC": "hash-c",
                ],
            ]
            environment.targetTestCacheItems = [
                projectPathOne: [
                    "TargetB": .test(
                        source: .local,
                        cacheCategory: .selectiveTests
                    ),
                    "TargetC": .test(
                        source: .remote,
                        cacheCategory: .selectiveTests
                    ),
                ],
            ]
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
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
            try await testRun(
                path: try temporaryPath()
            )

            // Then
            XCTAssertEqual(testedSchemes, ["ProjectSchemeOne"])
            XCTAssertStandardOutput(
                pattern:
                "The following targets have not changed since the last successful run and will be skipped: TargetB, TargetC"
            )
            let selectiveTestingCacheItems = await runMetadataStorage.selectiveTestingCacheItems
            XCTAssertEqual(
                selectiveTestingCacheItems,
                [
                    projectPathOne: [
                        "TargetA": .test(
                            name: "TargetA",
                            hash: "hash-a",
                            source: .miss,
                            cacheCategory: .selectiveTests
                        ),
                        "TargetB": .test(
                            source: .local,
                            cacheCategory: .selectiveTests
                        ),
                        "TargetC": .test(
                            source: .remote,
                            cacheCategory: .selectiveTests
                        ),
                    ],
                ]
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
    }

    func test_run_tests_stores_only_test_target_hashes_not_dependency_hashes() async throws {
        try await withMockedDependencies {
            // Given
            // TargetATests (.unitTests) depends on FrameworkA (.framework).
            // targetTestHashes contains hashes for both. Only the test target's hash
            // should be stored — the framework hash is already encoded in the test target hash.
            givenGenerator()
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.default)
            given(buildGraphInspector)
                .testableSchemes(graphTraverser: .any)
                .willReturn([])

            let projectPath = try temporaryPath().appending(component: "Project")
            let scheme = Scheme.test(
                name: "UnitTests",
                testAction: .test(
                    targets: [
                        .test(target: TargetReference(projectPath: projectPath, name: "TargetATests")),
                    ]
                )
            )

            given(buildGraphInspector)
                .workspaceSchemes(graphTraverser: .any)
                .willReturn([scheme])
            given(buildGraphInspector)
                .testableTarget(
                    scheme: .any,
                    testPlan: .any,
                    testTargets: .any,
                    skipTestTargets: .any,
                    graphTraverser: .any,
                    action: .any
                )
                .willReturn(.test())

            let testsTarget = Target.test(name: "TargetATests", product: .unitTests)
            let frameworkTarget = Target.test(name: "FrameworkA", product: .framework)
            let initialGraph = Graph.test(
                projects: [
                    projectPath: .test(
                        path: projectPath,
                        targets: [testsTarget, frameworkTarget],
                        schemes: [scheme]
                    ),
                ],
                dependencies: [
                    .target(name: testsTarget.name, path: projectPath): [
                        .target(name: frameworkTarget.name, path: projectPath),
                    ],
                ]
            )

            var environment = MapperEnvironment()
            environment.initialGraph = initialGraph
            environment.targetTestHashes = [
                projectPath: [
                    "TargetATests": "hash-tests",
                    "FrameworkA": "hash-fw",
                ],
            ]

            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in (path, initialGraph, environment) }

            // When
            try await testRun(path: try temporaryPath())

            // Then: only the test target hash is stored, not the framework dependency
            verify(cacheStorage)
                .store(
                    .value([CacheStorableItem(name: "TargetATests", hash: "hash-tests"): []]),
                    cacheCategory: .value(.selectiveTests)
                )
                .called(1)
            verify(cacheStorage)
                .store(
                    .value([CacheStorableItem(name: "FrameworkA", hash: "hash-fw"): []]),
                    cacheCategory: .value(.selectiveTests)
                )
                .called(0)
        }
    }

    func test_run_tests_caches_passing_targets_when_some_targets_fail() async throws {
        // Given
        let projectPath = try temporaryPath().appending(component: "ProjectOne")
        givenGenerator()

        let scheme = Scheme.test(
            name: "UnitTests",
            testAction: .test(
                targets: [
                    .test(target: .init(projectPath: projectPath, name: "FrameworkATests")),
                    .test(target: .init(projectPath: projectPath, name: "FrameworkBTests")),
                ]
            )
        )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    scheme,
                ]
            )

        let graph: Graph = .test(
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "FrameworkATests",
                            bundleId: "dev.tuist.FrameworkATests"
                        ),
                        .test(
                            name: "FrameworkBTests",
                            bundleId: "dev.tuist.FrameworkBTests"
                        ),
                    ]
                ),
            ]
        )

        var environment = MapperEnvironment()
        environment.initialGraph = graph
        environment.targetTestHashes = [
            projectPath: [
                "FrameworkATests": "hash-a",
                "FrameworkBTests": "hash-b",
            ],
        ]

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, graph, environment)
            }

        xcodebuildController.reset()

        let xcresultPath = try temporaryPath().appending(component: "bundle.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .value(xcresultPath),
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _, _ in
                self.testedSchemes.append(scheme)
                throw NSError.test()
            }

        given(xcResultService)
            .parse(path: .value(xcresultPath), rootDirectory: .any)
            .willReturn(
                TestSummary(
                    testPlanName: nil,
                    status: .failed,
                    duration: nil,
                    testModules: [
                        TestModule(
                            name: "FrameworkATests",
                            status: .failed,
                            duration: 0,
                            testSuites: [],
                            testCases: [
                                TestCase(
                                    name: "testA",
                                    testSuite: nil,
                                    module: "FrameworkATests",
                                    duration: nil,
                                    status: .failed,
                                    failures: []
                                ),
                            ]
                        ),
                        TestModule(
                            name: "FrameworkBTests",
                            status: .passed,
                            duration: 0,
                            testSuites: [],
                            testCases: [
                                TestCase(
                                    name: "testB",
                                    testSuite: nil,
                                    module: "FrameworkBTests",
                                    duration: nil,
                                    status: .passed,
                                    failures: []
                                ),
                            ]
                        ),
                    ]
                )
            )
        xcResultService.reset()
        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willReturn(nil)
        given(xcResultService)
            .parseTestStatuses(path: .any)
            .willReturn(
                TestResultStatuses(testCases: [
                    .init(name: "testA", testSuite: nil, module: "FrameworkATests", status: .failed),
                    .init(name: "testB", testSuite: nil, module: "FrameworkBTests", status: .passed),
                ])
            )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When / Then
        do {
            try await testRun(
                path: try temporaryPath(),
                resultBundlePath: xcresultPath
            )
            XCTFail("Should throw")
        } catch {}
        XCTAssertEqual(
            testedSchemes,
            [
                "UnitTests",
            ]
        )

        verify(cacheStorage)
            .store(
                .value(
                    [
                        CacheStorableItem(name: "FrameworkATests", hash: "hash-a"): [],
                    ]
                ),
                cacheCategory: .value(.selectiveTests)
            )
            .called(0)

        verify(cacheStorage)
            .store(
                .value(
                    [
                        CacheStorableItem(name: "FrameworkBTests", hash: "hash-b"): [],
                    ]
                ),
                cacheCategory: .value(.selectiveTests)
            )
            .called(1)
    }

    func test_run_tests_preserves_original_error_when_result_bundle_does_not_exist() async throws {
        // Given
        givenGenerator()

        let scheme = Scheme.test(
            name: "UnitTests",
            testAction: .test(
                targets: [
                    .test(target: .init(projectPath: try temporaryPath(), name: "TargetTests")),
                ]
            )
        )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([scheme])

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, .test(), MapperEnvironment())
            }

        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])

        let xcresultPath = try temporaryPath().appending(component: "bundle.xcresult")
        let originalError = NSError(domain: "xcodebuild", code: 70, userInfo: [
            NSLocalizedDescriptionKey: "Unable to find a device matching the provided destination specifier",
        ])

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any, scheme: .any, clean: .any, destination: .any, action: .any, rosetta: .any,
                derivedDataPath: .any, resultBundlePath: .value(xcresultPath), arguments: .any,
                retryCount: .any, testTargets: .any, skipTestTargets: .any,
                testPlanConfiguration: .any, passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _, _ in
                self.testedSchemes.append(scheme)
                throw originalError
            }

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When / Then
        do {
            try await testRun(
                path: try temporaryPath(),
                resultBundlePath: xcresultPath
            )
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, "xcodebuild")
            XCTAssertEqual((error as NSError).code, 70)
        }
        verify(xcResultService)
            .parseTestStatuses(path: .any)
            .called(0)
    }

    func test_run_tests_preserves_original_error_when_no_test_cases_in_result() async throws {
        // Given
        givenGenerator()

        let scheme = Scheme.test(
            name: "UnitTests",
            testAction: .test(
                targets: [
                    .test(target: .init(projectPath: try temporaryPath(), name: "TargetTests")),
                ]
            )
        )
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([scheme])

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, .test(), MapperEnvironment())
            }

        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])

        let xcresultPath = try temporaryPath().appending(component: "bundle.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)

        let originalError = NSError(domain: "xcodebuild", code: 70, userInfo: [
            NSLocalizedDescriptionKey: "Unable to find a device matching the provided destination specifier",
        ])

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any, scheme: .any, clean: .any, destination: .any, action: .any, rosetta: .any,
                derivedDataPath: .any, resultBundlePath: .value(xcresultPath), arguments: .any,
                retryCount: .any, testTargets: .any, skipTestTargets: .any,
                testPlanConfiguration: .any, passthroughXcodeBuildArguments: .any
            )
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _, _ in
                self.testedSchemes.append(scheme)
                throw originalError
            }

        xcResultService.reset()
        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willReturn(nil)
        given(xcResultService)
            .parseTestStatuses(path: .any)
            .willReturn(TestResultStatuses(testCases: []))

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When / Then
        do {
            try await testRun(
                path: try temporaryPath(),
                resultBundlePath: xcresultPath
            )
            XCTFail("Should throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, "xcodebuild")
            XCTAssertEqual((error as NSError).code, 70)
        }
    }

    func test_run_tests_when_part_is_cached_and_scheme_is_passed() async throws {
        try await withMockedDependencies {
            // Given
            givenGenerator()

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

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))
            given(buildGraphInspector)
                .workspaceSchemes(graphTraverser: .any)
                .willReturn([schemeOne, schemeTwo])
            given(buildGraphInspector)
                .testableTarget(
                    scheme: .any,
                    testPlan: .any,
                    testTargets: .any,
                    skipTestTargets: .any,
                    graphTraverser: .any,
                    action: .any
                )
                .willReturn(.test())
            var environment = MapperEnvironment()
            environment.initialGraph = .test(
                projects: [
                    projectPathOne: .test(
                        path: projectPathOne,
                        targets: [
                            .test(name: "TargetA", bundleId: "dev.tuist.TargetA"),
                            .test(name: "TargetB", bundleId: "dev.tuist.TargetB"),
                            .test(name: "TargetC", bundleId: "dev.tuist.TargetC"),
                            .test(name: "TargetD", bundleId: "dev.tuist.TargetD"),
                        ],
                        schemes: [
                            .test(
                                name: "ProjectSchemeOne",
                                testAction: .test(
                                    targets: [
                                        .test(
                                            target: TargetReference(
                                                projectPath: projectPathOne, name: "TargetA"
                                            )
                                        ),
                                        .test(
                                            target: TargetReference(
                                                projectPath: projectPathOne, name: "TargetB"
                                            )
                                        ),
                                    ]
                                )
                            ),
                            .test(
                                name: "ProjectSchemeTwo",
                                testAction: .test(
                                    targets: [
                                        .test(
                                            target: TargetReference(
                                                projectPath: projectPathOne, name: "TargetC"
                                            )
                                        ),
                                        .test(
                                            target: TargetReference(
                                                projectPath: projectPathOne, name: "TargetD"
                                            )
                                        ),
                                    ]
                                )
                            ),
                        ]
                    ),
                ]
            )
            environment.targetTestHashes = [
                projectPathOne: [
                    "TargetA": "hash-a",
                    "TargetB": "hash-b",
                    "TargetC": "hash-c",
                    "TargetD": "hash-d",
                ],
            ]
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
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
            try await testRun(
                schemeName: "ProjectSchemeTwo",
                path: try temporaryPath()
            )

            // Then
            XCTAssertEqual(testedSchemes, ["ProjectSchemeTwo"])
            XCTAssertStandardOutput(
                pattern:
                "The following targets have not changed since the last successful run and will be skipped: TargetC"
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
    }

    func test_run_tests_with_skipped_targets() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .value([]),
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .willReturn(generator)
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
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOneTests")])),
                    MapperEnvironment()
                )
            }

        // When
        try await testRun(
            schemeName: "ProjectSchemeOneTests",
            path: try temporaryPath(),
            skipTestTargets: [.init(target: "ProjectSchemeOneTests", class: "TestClass")]
        )

        // Then
        XCTAssertEqual(testedSchemes, ["ProjectSchemeOneTests"])
    }

    func test_run_filters_test_targets_not_in_scheme() async throws {
        // Given
        // Scheme has only "TargetA" in its test action — "PrunedTarget" was removed by selective testing
        let projectPath = try temporaryPath().appending(component: "Project")
        let scheme = Scheme.test(
            name: "App-Workspace",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPath, name: "TargetA")),
                ]
            )
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .willReturn(generator)
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(
                        projects: [
                            projectPath: .test(
                                path: projectPath,
                                targets: [.test(name: "TargetA")],
                                schemes: [scheme]
                            ),
                        ]
                    ),
                    MapperEnvironment()
                )
            }
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([scheme])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .any,
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        var capturedTestTargets: [TestIdentifier]?
        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, testTargets, _, _, _ in
                capturedTestTargets = testTargets
                self.testedSchemes.append(scheme)
            }

        // When — user passes both TargetA (present) and PrunedTarget (not in scheme)
        try await testRun(
            path: try temporaryPath(),
            testTargets: [
                try .init(target: "TargetA", class: nil),
                try .init(target: "PrunedTarget", class: nil),
            ]
        )

        // Then — only TargetA should be passed to xcodebuild, PrunedTarget should be filtered out
        XCTAssertEqual(testedSchemes, ["App-Workspace"])
        XCTAssertEqual(capturedTestTargets, [try TestIdentifier(target: "TargetA", class: nil)])
    }

    func test_run_skips_xcodebuild_when_passthrough_skip_testing_removes_all_selective_targets() async throws {
        // Given — selective testing has filtered the graph so that only "SkippedTarget"
        // remains in the scheme. The user also passes `-skip-testing:SkippedTarget` as a
        // passthrough xcodebuild argument, which would leave xcodebuild with nothing to
        // test (exit code 2). tuist should short-circuit and NOT invoke xcodebuild.
        let projectPath = try temporaryPath().appending(component: "Project")
        let filteredScheme = Scheme.test(
            name: "App-Workspace",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPath, name: "SkippedTarget")),
                ]
            )
        )
        let initialScheme = Scheme.test(
            name: "App-Workspace",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPath, name: "CleanTarget")),
                    .test(target: TargetReference(projectPath: projectPath, name: "SkippedTarget")),
                ]
            )
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .willReturn(generator)

        var environment = MapperEnvironment()
        environment.initialGraph = .test(
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "CleanTarget", product: .unitTests, bundleId: "dev.tuist.Clean"),
                        .test(name: "SkippedTarget", product: .unitTests, bundleId: "dev.tuist.Skipped"),
                    ],
                    schemes: [initialScheme]
                ),
            ]
        )

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(
                        projects: [
                            projectPath: .test(
                                path: projectPath,
                                targets: [
                                    .test(name: "SkippedTarget", product: .unitTests, bundleId: "dev.tuist.Skipped"),
                                ],
                                schemes: [filteredScheme]
                            ),
                        ]
                    ),
                    environment
                )
            }
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([filteredScheme])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .any,
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _, _ in
                self.testedSchemes.append(scheme)
            }

        // When
        try await testRun(
            path: try temporaryPath(),
            passthroughXcodeBuildArguments: ["-skip-testing:SkippedTarget"]
        )

        // Then — xcodebuild should NOT have been invoked (would otherwise exit 2).
        XCTAssertEmpty(testedSchemes)
    }

    func test_run_invokes_xcodebuild_when_passthrough_skip_testing_targets_a_class_within_remaining_target() async throws {
        // Given — selective testing has filtered the graph so only "TargetA" remains,
        // and the user passes `-skip-testing:TargetA/SomeClass` (a scoped skip). The
        // target still has tests to run, so xcodebuild should still be invoked.
        let projectPath = try temporaryPath().appending(component: "Project")
        let scheme = Scheme.test(
            name: "App-Workspace",
            testAction: .test(
                targets: [
                    .test(target: TargetReference(projectPath: projectPath, name: "TargetA")),
                ]
            )
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .willReturn(generator)
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    .test(
                        projects: [
                            projectPath: .test(
                                path: projectPath,
                                targets: [.test(name: "TargetA", product: .unitTests)],
                                schemes: [scheme]
                            ),
                        ]
                    ),
                    MapperEnvironment()
                )
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([scheme])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .any,
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        // When
        try await testRun(
            path: try temporaryPath(),
            passthroughXcodeBuildArguments: ["-skip-testing:TargetA/SomeClass"]
        )

        // Then — xcodebuild SHOULD be invoked; a scoped skip does not remove the whole target.
        XCTAssertEqual(testedSchemes, ["App-Workspace"])
    }

    func test_run_tests_all_project_schemes_when_fails() async throws {
        // Given
        givenGenerator()
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectScheme"),
                ]
            )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, .test(), MapperEnvironment())
            }
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([])
        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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
            .willProduce { _, scheme, _, _, _, _, _, _, _, _, _, _, _, _ in
                self.testedSchemes.append(scheme)
                throw NSError.test()
            }
        try await fileSystem.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When / Then
        do {
            try await testRun(
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
    }

    func test_run_tests_when_no_project_schemes_present() async throws {
        try await withMockedDependencies {
            // Given
            givenGenerator()

            let graph: Graph = .test()
            var environment = MapperEnvironment()
            environment.initialGraph = graph
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (path, .test(), environment)
                }
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject()))

            // When
            try await testRun(
                path: try temporaryPath()
            )

            // Then
            XCTAssertEmpty(testedSchemes)
            XCTAssertPrinterOutputContains("There are no tests to run, finishing early")
        }
    }

    func test_run_uses_resource_bundle_path() async throws {
        // Given
        givenGenerator()
        let expectedResourceBundlePath = try temporaryPath()
            .appending(component: "test")
        let xcresultPath = expectedResourceBundlePath.parentDirectory.appending(
            component: "bundle.xcresult"
        )
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.createSymbolicLink(
            from: expectedResourceBundlePath,
            to: expectedResourceBundlePath.parentDirectory.appending(component: "bundle.xcresult")
        )
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
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
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            path: try temporaryPath(),
            resultBundlePath: expectedResourceBundlePath
        )

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .value(expectedResourceBundlePath),
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_uses_resource_bundle_path_when_not_a_symlink() async throws {
        // Given
        givenGenerator()
        let xcresultPath = try temporaryPath().appending(component: "bundle.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, .test(), MapperEnvironment())
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectScheme"),
                ]
            )

        // When
        try await testRun(
            path: try temporaryPath(),
            resultBundlePath: xcresultPath
        )

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .value(xcresultPath),
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_saves_resource_bundle_when_cloud_is_configured() async throws {
        // Given
        givenGenerator()
        configLoader.reset()
        let expectedResultBundlePath =
            try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: "run-id", Constants.resultBundleName)

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, .test(), MapperEnvironment())
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn(
                [
                    Scheme.test(name: "ProjectScheme"),
                ]
            )
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

        try await fileSystem.makeDirectory(at: runsCacheDirectory)

        // When
        try await testRun(
            runId: "run-id",
            path: try temporaryPath()
        )

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .value(expectedResultBundlePath),
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_uses_resource_bundle_path_with_given_scheme() async throws {
        // Given
        givenGenerator()
        let expectedResourceBundlePath = try temporaryPath()
            .appending(component: "test")
        let xcresultPath = expectedResourceBundlePath.parentDirectory.appending(
            component: "bundle.xcresult"
        )
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.createSymbolicLink(
            from: expectedResourceBundlePath,
            to: expectedResourceBundlePath.parentDirectory.appending(component: "bundle.xcresult")
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "ProjectScheme2")])),
                    MapperEnvironment()
                )
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

        // When
        try await testRun(
            schemeName: "ProjectScheme2",
            path: try temporaryPath(),
            resultBundlePath: expectedResourceBundlePath
        )

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .value(expectedResourceBundlePath),
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
        let existsResultBundlePathInCacheDirectory = try await fileSystem.exists(
            try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)
                .appending(components: "run-id", "\(Constants.resultBundleName).xcresult"),
            isDirectory: true
        )
        XCTAssertTrue(existsResultBundlePathInCacheDirectory)
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
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOne")])),
                    MapperEnvironment()
                )
            }

        // When
        try await testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath(),
            retryCount: 3
        )

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .value(3),
                testTargets: .any,
                skipTestTargets: .any,
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_defaults_retry_count_to_zero() async throws {
        // Given
        givenGenerator()
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
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "ProjectSchemeOne")])),
                    MapperEnvironment()
                )
            }

        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
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
                action: .any,
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
        let testPlan = "TestPlan"
        let testPlanPath = try AbsolutePath(validating: "/testPlan/\(testPlan)")
        let projectPath = try temporaryPath().appending(component: "Project")
        let projectTestableSchemes = [
            Scheme.test(
                name: "TestScheme",
                testAction: .test(
                    targets: [
                        .test(
                            // This target's hash should _not_ be stored
                            // as only targets in the test plan were tested.
                            target: TargetReference(
                                projectPath: projectPath,
                                name: "TargetB"
                            )
                        ),
                    ],
                    testPlans: [
                        .init(
                            path: testPlanPath,
                            testTargets: [
                                .test(
                                    target: TargetReference(
                                        projectPath: projectPath,
                                        name: "TargetA"
                                    )
                                ),
                            ],
                            isDefault: true
                        ),
                    ]
                )
            ),
        ]

        let graph: Graph = .test(
            workspace: .test(
                schemes: [
                    Scheme.test(name: "App-Workspace"),
                ]
            ),
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "TargetA",
                            bundleId: "dev.tuist.TargetA"
                        ),
                        .test(
                            name: "TargetB",
                            bundleId: "dev.tuist.TargetB"
                        ),
                    ],
                    schemes: projectTestableSchemes
                ),
            ]
        )

        var environment = MapperEnvironment()
        environment.targetTestCacheItems = [
            projectPath: [
                "a": CacheItem.test(
                    name: "A"
                ),
                "b": CacheItem.test(
                    name: "B"
                ),
            ],
        ]
        environment.initialGraph = graph
        environment.targetTestHashes = [
            projectPath: [
                "TargetA": "hash-a",
                "TargetB": "hash-b",
            ],
        ]
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    graph,
                    environment
                )
            }

        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(projectTestableSchemes)
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .value(testPlan),
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willProduce { scheme, _, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            testPlanConfiguration: TestPlanConfiguration(testPlan: testPlan)
        )

        // Then
        XCTAssertEqual(testedSchemes, ["TestScheme"])
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
        let selectiveTestingCacheItems = await runMetadataStorage.selectiveTestingCacheItems
        XCTAssertEqual(
            selectiveTestingCacheItems,
            [
                projectPath: [
                    "TargetA": .test(
                        name: "TargetA",
                        hash: "hash-a",
                        source: .miss,
                        cacheCategory: .selectiveTests
                    ),
                ],
            ]
        )
    }

    func test_run_test_plan_with_no_explicit_targets() async throws {
        // Given
        givenGenerator()
        let testPlan = "TestPlan"
        let testPlanPath = try AbsolutePath(validating: "/testPlan/\(testPlan)")
        let projectPath = try temporaryPath().appending(component: "Project")
        let projectTestableSchemes = [
            Scheme.test(
                name: "TestScheme",
                testAction: .test(
                    targets: [],
                    testPlans: [
                        .init(
                            path: testPlanPath,
                            testTargets: [
                                .test(
                                    target: TargetReference(
                                        projectPath: projectPath,
                                        name: "TargetA"
                                    )
                                ),
                            ],
                            isDefault: true
                        ),
                    ]
                )
            ),
        ]

        let graph: Graph = .test(
            workspace: .test(
                schemes: [
                    Scheme.test(name: "App-Workspace"),
                ]
            ),
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "TargetA",
                            bundleId: "dev.tuist.TargetA"
                        ),
                        .test(
                            name: "TargetB",
                            bundleId: "dev.tuist.TargetB"
                        ),
                    ],
                    schemes: projectTestableSchemes
                ),
            ]
        )

        var environment = MapperEnvironment()
        environment.targetTestCacheItems = [
            projectPath: [
                "a": CacheItem.test(
                    name: "A"
                ),
                "b": CacheItem.test(
                    name: "B"
                ),
            ],
        ]
        environment.initialGraph = graph
        environment.targetTestHashes = [
            projectPath: [
                "TargetA": "hash-a",
                "TargetB": "hash-b",
            ],
        ]
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    graph,
                    environment
                )
            }

        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(projectTestableSchemes)
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .value(testPlan),
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willProduce { scheme, _, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            testPlanConfiguration: TestPlanConfiguration(testPlan: testPlan)
        )

        // Then
        XCTAssertEqual(testedSchemes, ["TestScheme"])
        let selectiveTestingCacheItems = await runMetadataStorage.selectiveTestingCacheItems
        XCTAssertEqual(
            selectiveTestingCacheItems,
            [
                projectPath: [
                    "TargetA": .test(
                        name: "TargetA",
                        hash: "hash-a",
                        source: .miss
                    ),
                ],
            ]
        )
    }

    func test_build_scheme_with_test_plans_and_no_explicit_targets() async throws {
        // Given
        givenGenerator()
        let testPlan = "TestPlan1"
        let testPlan2 = "TestPlan2"
        let testPlanPath = try AbsolutePath(validating: "/testPlan/\(testPlan)")
        let testPlan2Path = try AbsolutePath(validating: "/testPlan/\(testPlan2)")
        let projectPath = try temporaryPath().appending(component: "Project")
        let projectTestableSchemes = [
            Scheme.test(
                name: "TestScheme",
                testAction: .test(
                    targets: [],
                    testPlans: [
                        .init(
                            path: testPlanPath,
                            testTargets: [
                                .test(
                                    target: TargetReference(
                                        projectPath: projectPath,
                                        name: "TargetA"
                                    )
                                ),
                            ],
                            isDefault: true
                        ),
                        .init(
                            path: testPlan2Path,
                            testTargets: [
                                .test(
                                    target: TargetReference(
                                        projectPath: projectPath,
                                        name: "TargetB"
                                    )
                                ),
                            ],
                            isDefault: true
                        ),
                    ]
                )
            ),
        ]

        let graph: Graph = .test(
            workspace: .test(
                schemes: [
                    Scheme.test(name: "App-Workspace"),
                ]
            ),
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(
                            name: "TargetA",
                            bundleId: "dev.tuist.TargetA"
                        ),
                        .test(
                            name: "TargetB",
                            bundleId: "dev.tuist.TargetB"
                        ),
                    ],
                    schemes: projectTestableSchemes
                ),
            ]
        )

        var environment = MapperEnvironment()
        environment.targetTestCacheItems = [
            projectPath: [
                "a": CacheItem.test(
                    name: "A"
                ),
                "b": CacheItem.test(
                    name: "B"
                ),
            ],
        ]
        environment.initialGraph = graph
        environment.targetTestHashes = [
            projectPath: [
                "TargetA": "hash-a",
                "TargetB": "hash-b",
            ],
        ]
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path,
                    graph,
                    environment
                )
            }

        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(projectTestableSchemes)
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .any,
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willProduce { scheme, _, _, _, _, _ in
                GraphTarget.test(
                    target: Target.test(
                        name: scheme.name
                    )
                )
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            action: .build
        )

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .value("TestScheme"),
                clean: .any,
                destination: .any,
                action: .value(.build),
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
            .called(1)
    }

    func test_run_test_plan_failure() async throws {
        // Given
        givenGenerator()
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
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])),
                    MapperEnvironment()
                )
            }
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        let notDefinedTestPlan = "NotDefined"
        do {
            // When
            try await testRun(
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

    func test_run_logsWarningWhenInspectResultBundleFails() async throws {
        try await withMockedDependencies {
            // Given
            givenGenerator()
            given(buildGraphInspector)
                .workspaceSchemes(graphTraverser: .any)
                .willReturn(
                    [
                        Scheme.test(name: "ProjectScheme"),
                    ]
                )
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willProduce { path, _ in
                    (path, .test(), MapperEnvironment())
                }

            let resultBundlePath = try temporaryPath().appending(component: "test.xcresult")
            try await fileSystem.makeDirectory(at: resultBundlePath)

            configLoader.reset()
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(
                    .test(
                        project: .testGeneratedProject(),
                        fullHandle: "tuist/tuist",
                        url: URL(string: "https://example.com")!
                    )
                )

            xcResultService.reset()
            given(xcResultService)
                .parse(path: .any, rootDirectory: .any)
                .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 0, testModules: []))

            uploadResultBundleService.reset()
            given(uploadResultBundleService)
                .uploadTestSummary(
                    testSummary: .any,
                    projectDerivedDataDirectory: .any,
                    config: .any,
                    shardPlanId: .any,
                    shardIndex: .any
                )
                .willThrow(TestError("Inspect failed"))

            // When
            try await testRun(
                path: try temporaryPath(),
                resultBundlePath: resultBundlePath
            )

            // Then
            XCTAssertEqual(testedSchemes, ["ProjectScheme"])
            let warnings = AlertController.current.warnings()
            XCTAssertEqual(warnings.count, 1)
            XCTAssertTrue(warnings.first?.message.plain().contains("Failed to upload test results") == true)
        }
    }

    func test_run_fetches_quarantined_tests_and_runs_them() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let fullHandle = "organization/project"

        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject(), fullHandle: fullHandle))

        testCaseListService.reset()
        given(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .value(.muted))
            .willReturn([
                try TestIdentifier(target: "AppTests", class: "QuarantinedSuite", method: "testQuarantined()"),
                try TestIdentifier(target: "CoreTests", class: nil, method: "testAnotherQuarantined()"),
            ])
        given(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .value(.skipped))
            .willReturn([])
        testQuarantineService.reset()
        given(testQuarantineService)
            .markQuarantinedTests(testSummary: .any, quarantinedTests: .any)
            .willProduce { summary, _ in summary }
        given(testQuarantineService)
            .onlyQuarantinedTestsFailed(testSummary: .any)
            .willReturn(false)

        buildGraphInspector.reset()
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        given(generator)
            .generateWithGraph(path: .value(path), options: .any)
            .willProduce { path, _ in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectScheme")])), MapperEnvironment())
            }

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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

        // When
        try await testRun(path: path)

        // Then - quarantined tests are NOT skipped, they run normally
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .value([]),
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_passes_skipped_quarantined_tests_as_skip_testing() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let fullHandle = "organization/project"

        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject(), fullHandle: fullHandle))

        let skippedIdentifier = try TestIdentifier(
            target: "CoreTests",
            class: "SlowSuite",
            method: "testSuperSlow()"
        )

        testCaseListService.reset()
        given(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .value(.muted))
            .willReturn([
                try TestIdentifier(target: "AppTests", class: "FlakySuite", method: "testFlaky()"),
            ])
        given(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .value(.skipped))
            .willReturn([skippedIdentifier])
        testQuarantineService.reset()
        given(testQuarantineService)
            .markQuarantinedTests(testSummary: .any, quarantinedTests: .any)
            .willProduce { summary, _ in summary }
        given(testQuarantineService)
            .onlyQuarantinedTestsFailed(testSummary: .any)
            .willReturn(false)

        buildGraphInspector.reset()
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        given(generator)
            .generateWithGraph(path: .value(path), options: .any)
            .willProduce { path, _ in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectScheme")])), MapperEnvironment())
            }

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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

        // When
        try await testRun(path: path)

        // Then — skipped quarantined tests land in skipTestTargets; muted ones don't.
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .value([skippedIdentifier]),
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_does_not_fetch_quarantined_tests_when_skipQuarantine_is_true() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let fullHandle = "organization/project"

        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject(), fullHandle: fullHandle))

        buildGraphInspector.reset()
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        given(generator)
            .generateWithGraph(path: .value(path), options: .any)
            .willProduce { path, _ in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectScheme")])), MapperEnvironment())
            }

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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

        // When
        try await testRun(path: path, skipQuarantine: true)

        // Then — `--skip-quarantine` short-circuits the fetch entirely.
        verify(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .any)
            .called(0)
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .value([]),
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_does_not_fetch_quarantined_tests_when_fullHandle_is_nil() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()

        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject(), fullHandle: nil))

        buildGraphInspector.reset()
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        given(generator)
            .generateWithGraph(path: .value(path), options: .any)
            .willProduce { path, _ in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectScheme")])), MapperEnvironment())
            }

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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

        // When
        try await testRun(path: path)

        // Then — fullHandle is nil so the fetch is skipped entirely.
        verify(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .any)
            .called(0)
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .value([]),
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    func test_run_logs_warning_when_fetching_quarantined_tests_fails() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let fullHandle = "organization/project"

        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject(), fullHandle: fullHandle))

        testCaseListService.reset()
        given(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .any)
            .willReturn([])
        testQuarantineService.reset()
        given(testQuarantineService)
            .markQuarantinedTests(testSummary: .any, quarantinedTests: .any)
            .willProduce { summary, _ in summary }
        given(testQuarantineService)
            .onlyQuarantinedTestsFailed(testSummary: .any)
            .willReturn(false)

        buildGraphInspector.reset()
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([Scheme.test(name: "ProjectScheme")])
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any, testPlan: .any, testTargets: .any, skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willReturn(.test())

        given(generator)
            .generateWithGraph(path: .value(path), options: .any)
            .willProduce { path, _ in
                (path, .test(workspace: .test(schemes: [.test(name: "ProjectScheme")])), MapperEnvironment())
            }

        xcodebuildController.reset()
        given(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
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

        // When
        try await testRun(path: path)

        // Then
        verify(xcodebuildController)
            .test(
                .any,
                scheme: .any,
                clean: .any,
                destination: .any,
                action: .any,
                rosetta: .any,
                derivedDataPath: .any,
                resultBundlePath: .any,
                arguments: .any,
                retryCount: .any,
                testTargets: .any,
                skipTestTargets: .value([]),
                testPlanConfiguration: .any,
                passthroughXcodeBuildArguments: .any
            )
            .called(1)
    }

    private func givenGenerator() {
        given(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .willReturn(generator)
    }

    func test_run_testWithoutBuilding_skipsGeneration_whenSelectiveTestingGraphExists() async throws {
        // Given
        let path = try temporaryPath()
        let testProductsPath = path.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)

        let selectiveTestingGraph = SelectiveTestingGraph(
            testTargetHashes: ["MyTests": "abc123"]
        )
        let graphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        let data = try JSONEncoder().encode(selectiveTestingGraph)
        try data.write(to: graphPath.url)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        given(xcodebuildController)
            .run(arguments: .any)
            .willReturn(())

        // When
        try await AlertController.$current.withValue(AlertController()) {
            try await testRun(
                path: path,
                action: .testWithoutBuilding,
                passthroughXcodeBuildArguments: ["-testProductsPath", testProductsPath.pathString]
            )
        }

        // Then — generator should NOT have been called
        verify(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .called(0)

        // xcodebuild test-without-building should have been called
        verify(xcodebuildController)
            .run(arguments: .any)
            .called(1)
    }

    func test_run_testWithoutBuilding_fallsBackToGeneration_whenNoSelectiveTestingGraph() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let testProductsPath = path.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, .test(workspace: .test(schemes: [.test(name: "TestScheme")])),
                    MapperEnvironment()
                )
            }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([.test(name: "TestScheme")])

        // When
        try await testRun(
            path: path,
            action: .testWithoutBuilding,
            passthroughXcodeBuildArguments: ["-testProductsPath", testProductsPath.pathString]
        )

        // Then — generator SHOULD have been called since no graph file exists
        verify(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .called(1)
    }

    func test_run_testWithoutBuilding_skipsWhenSelectedTestPlanTargetsWereFullyCached() async throws {
        // Given
        let path = try temporaryPath()
        let testProductsPath = path.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        let testPlan = "IntegrationTestSuite"

        let selectiveTestingGraph = SelectiveTestingGraph(
            testTargetHashes: ["IntegrationTests": "abc123"]
        )
        let graphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        let data = try JSONEncoder().encode(selectiveTestingGraph)
        try data.write(to: graphPath.url)
        let runMetadata = SelectiveTestingRunMetadata(
            selectedTargetNames: ["IntegrationTests"],
            runnableTargetNames: []
        )
        let metadataPath = testProductsPath.appending(component: SelectiveTestingRunMetadata.fileName)
        let metadataData = try JSONEncoder().encode(runMetadata)
        try metadataData.write(to: metadataPath.url)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await AlertController.$current.withValue(AlertController()) {
            try await testRun(
                path: path,
                action: .testWithoutBuilding,
                testPlanConfiguration: TestPlanConfiguration(testPlan: testPlan),
                passthroughXcodeBuildArguments: ["-testProductsPath", testProductsPath.pathString]
            )
        }

        // Then
        verify(generatorFactory)
            .testing(
                config: .any,
                testPlan: .any,
                includedTargets: .any,
                excludedTargets: .any,
                skipUITests: .any,
                skipUnitTests: .any,
                configuration: .any,
                ignoreBinaryCache: .any,
                ignoreSelectiveTesting: .any,
                cacheStorage: .any,
                destination: .any,
                schemeName: .any
            )
            .called(0)

        verify(xcodebuildController)
            .run(arguments: .any)
            .called(0)
    }

    func test_run_testWithoutBuilding_skipsWhenSelectedSchemeTargetsWereFullyCached() async throws {
        // Given
        let path = try temporaryPath()
        let testProductsPath = path.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)

        let selectiveTestingGraph = SelectiveTestingGraph(
            testTargetHashes: ["UnitTests": "abc123"]
        )
        let graphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        let data = try JSONEncoder().encode(selectiveTestingGraph)
        try data.write(to: graphPath.url)
        let runMetadata = SelectiveTestingRunMetadata(
            selectedTargetNames: ["UnitTests"],
            runnableTargetNames: []
        )
        let metadataPath = testProductsPath.appending(component: SelectiveTestingRunMetadata.fileName)
        let metadataData = try JSONEncoder().encode(runMetadata)
        try metadataData.write(to: metadataPath.url)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await AlertController.$current.withValue(AlertController()) {
            try await testRun(
                path: path,
                action: .testWithoutBuilding,
                passthroughXcodeBuildArguments: ["-testProductsPath", testProductsPath.pathString]
            )
        }

        // Then
        verify(xcodebuildController)
            .run(arguments: .any)
            .called(0)
    }

    func test_run_testWithoutBuilding_doesNotSkipWhenRunnableTargetsRemain() async throws {
        // Given
        let path = try temporaryPath()
        let testProductsPath = path.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        let requestedTestPlan = "IntegrationTestSuite"

        let selectiveTestingGraph = SelectiveTestingGraph(
            testTargetHashes: ["UnitTests": "abc123"]
        )
        let graphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        let data = try JSONEncoder().encode(selectiveTestingGraph)
        try data.write(to: graphPath.url)
        let runMetadata = SelectiveTestingRunMetadata(
            selectedTargetNames: ["UnitTests"],
            runnableTargetNames: ["UnitTests"]
        )
        let metadataPath = testProductsPath.appending(component: SelectiveTestingRunMetadata.fileName)
        let metadataData = try JSONEncoder().encode(runMetadata)
        try metadataData.write(to: metadataPath.url)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        let error = SystemError.terminated(
            command: "xcodebuild test-without-building",
            code: 66,
            standardError: Data("xcodebuild: error: xctestproducts does not contain test plan: \(requestedTestPlan)".utf8)
        )
        given(xcodebuildController)
            .run(arguments: .any)
            .willThrow(error)

        // When / Then
        await XCTAssertThrowsSpecific(
            {
                try await testRun(
                    path: path,
                    action: .testWithoutBuilding,
                    testPlanConfiguration: TestPlanConfiguration(testPlan: requestedTestPlan),
                    passthroughXcodeBuildArguments: ["-testProductsPath", testProductsPath.pathString]
                )
            },
            error
        )
    }

    func test_run_build_passesShardArchivePathToShardPlanService() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let testProductsPath = path.appending(component: "TestProducts.xctestproducts")
        let shardArchivePath = path.appending(components: "artifacts", "bundle.aar")
        let projectPath = AbsolutePath.root.appending(component: "Project")
        let scheme = Scheme.test(name: "ProjectScheme")
        let graph: Graph = .test(
            workspace: .test(schemes: [scheme]),
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [
                        .test(name: "AppTests", product: .unitTests),
                    ]
                ),
            ]
        )
        try await fileSystem.makeDirectory(at: testProductsPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject(), fullHandle: "tuist/tuist"))

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (
                    path, graph,
                    MapperEnvironment()
                )
            }

        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([scheme])

        given(shardPlanService)
            .plan(
                xctestproductsPath: .any,
                destination: .any,
                reference: .any,
                shardGranularity: .any,
                shardMin: .any,
                shardMax: .any,
                shardTotal: .any,
                shardMaxDuration: .any,
                fullHandle: .any,
                serverURL: .any,
                buildRunId: .any,
                skipUpload: .any,
                archivePath: .any
            )
            .willReturn(
                Components.Schemas.ShardPlan(
                    id: "plan-id",
                    reference: "ref",
                    shard_count: 2,
                    shards: []
                )
            )

        // When
        try await testRun(
            path: path,
            platform: "iOS",
            action: .build,
            passthroughXcodeBuildArguments: ["-testProductsPath", testProductsPath.pathString],
            shardTotal: 2,
            shardArchivePath: shardArchivePath
        )

        // Then
        verify(shardPlanService)
            .plan(
                xctestproductsPath: .value(testProductsPath),
                destination: .value("platform=iOS"),
                reference: .any,
                shardGranularity: .any,
                shardMin: .any,
                shardMax: .any,
                shardTotal: .value(2),
                shardMaxDuration: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                buildRunId: .any,
                skipUpload: .value(false),
                archivePath: .value(shardArchivePath)
            )
            .called(1)
    }

    func test_run_testWithoutBuilding_passesShardArchivePathToShardService() async throws {
        // Given
        let path = try temporaryPath()
        let shardArchivePath = path.appending(component: "bundle.aar")
        let extractedTestProductsPath = path.appending(component: "Extracted.xctestproducts")
        try await fileSystem.makeDirectory(at: extractedTestProductsPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject(), fullHandle: "tuist/tuist"))

        given(shardService)
            .shard(
                shardIndex: .any,
                fullHandle: .any,
                serverURL: .any,
                testProductsPath: .any,
                testProductsArchivePath: .any
            )
            .willReturn(
                Shard(
                    reference: "ref",
                    shardPlanId: "plan-123",
                    testProductsPath: extractedTestProductsPath,
                    xcTestRunPath: nil,
                    modules: ["AppTests"],
                    selectiveTestingGraph: nil
                )
            )

        given(xcodebuildController)
            .run(arguments: .any)
            .willReturn()

        // When
        try await AlertController.$current.withValue(AlertController()) {
            try await testRun(
                path: path,
                action: .testWithoutBuilding,
                shardIndex: 1,
                shardArchivePath: shardArchivePath
            )
        }

        // Then
        verify(shardService)
            .shard(
                shardIndex: .value(1),
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                testProductsPath: .value(nil),
                testProductsArchivePath: .value(shardArchivePath)
            )
            .called(1)
    }

    func test_run_build_writesSelectiveTestingGraph_whenTestProductsPathIsRelative() async throws {
        // Given
        givenGenerator()
        let path = try temporaryPath()
        let bundleName = "MyApp.xctestproducts"
        let testProductsPath = path.appending(component: bundleName)
        try await fileSystem.makeDirectory(at: testProductsPath)

        let projectPath = path.appending(component: "Project")
        let scheme = Scheme.test(name: "TestScheme")
        let graph: Graph = .test(
            workspace: .test(schemes: [.test(name: "App-Workspace")]),
            projects: [
                projectPath: .test(
                    path: projectPath,
                    targets: [.test(name: "TargetA")],
                    schemes: [scheme]
                ),
            ]
        )
        var environment = MapperEnvironment()
        environment.initialGraph = graph
        environment.targetTestHashes = [projectPath: ["TargetA": "hash-a"]]

        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in
                (path, graph, environment)
            }
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([scheme])
        given(buildGraphInspector)
            .testableTarget(
                scheme: .any,
                testPlan: .any,
                testTargets: .any,
                skipTestTargets: .any,
                graphTraverser: .any,
                action: .any
            )
            .willProduce { scheme, _, _, _, _, _ in
                GraphTarget.test(target: Target.test(name: scheme.name))
            }
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([])
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))

        // When
        try await testRun(
            schemeName: "TestScheme",
            path: path,
            action: .build,
            passthroughXcodeBuildArguments: ["-testProductsPath", bundleName]
        )

        // Then — the selective testing graph should have been written into the bundle
        let graphPath = testProductsPath.appending(component: SelectiveTestingGraph.fileName)
        let exists = try await fileSystem.exists(graphPath)
        XCTAssertTrue(exists, "Expected selective testing graph at \(graphPath.pathString)")
        let metadataPath = testProductsPath.appending(component: SelectiveTestingRunMetadata.fileName)
        let metadataExists = try await fileSystem.exists(metadataPath)
        XCTAssertTrue(metadataExists, "Expected selective testing metadata at \(metadataPath.pathString)")
    }

    fileprivate func testRun(
        runId: String = "run-id",
        schemeName: String? = nil,
        clean: Bool = false,
        noUpload: Bool = false,
        configuration: String? = nil,
        path: AbsolutePath,
        deviceName: String? = nil,
        platform: String? = nil,
        osVersion: String? = nil,
        action: XcodeBuildTestAction = .test,
        rosetta: Bool = false,
        skipUiTests: Bool = false,
        skipUnitTests: Bool = false,
        resultBundlePath: AbsolutePath? = nil,
        derivedDataPath: String? = nil,
        retryCount: Int = 0,
        testTargets: [TestIdentifier] = [],
        skipTestTargets: [TestIdentifier] = [],
        testPlanConfiguration: TestPlanConfiguration? = nil,
        generateOnly: Bool = false,
        passthroughXcodeBuildArguments: [String] = [],
        skipQuarantine: Bool = false,
        shardReference: String? = nil,
        shardMin: Int? = nil,
        shardMax: Int? = nil,
        shardTotal: Int? = nil,
        shardMaxDuration: Int? = nil,
        shardIndex: Int? = nil,
        shardSkipUpload: Bool = false,
        shardArchivePath: AbsolutePath? = nil,
        mode: TestProcessingMode? = .local
    ) async throws {
        try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
            try await subject.run(
                runId: runId,
                schemeName: schemeName,
                clean: clean,
                noUpload: noUpload,
                configuration: configuration,
                path: path,
                deviceName: deviceName,
                platform: platform,
                osVersion: osVersion,
                action: action,
                rosetta: rosetta,
                skipUITests: skipUiTests,
                skipUnitTests: skipUnitTests,
                resultBundlePath: resultBundlePath,
                derivedDataPath: derivedDataPath,
                retryCount: retryCount,
                testTargets: testTargets,
                skipTestTargets: skipTestTargets,
                testPlanConfiguration: testPlanConfiguration,
                ignoreBinaryCache: false,
                ignoreSelectiveTesting: false,
                generateOnly: generateOnly,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                skipQuarantine: skipQuarantine,
                shardReference: shardReference,
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration,
                shardIndex: shardIndex,
                shardSkipUpload: shardSkipUpload,
                shardArchivePath: shardArchivePath,
                mode: mode
            )
        }
    }

    // MARK: - inferPlatformDestination

    func test_inferPlatformDestination_returns_nil_for_empty_schemes() {
        let graphTraverser = MockGraphTraversing()
        XCTAssertNil(subject.inferPlatformDestination(schemes: [], graphTraverser: graphTraverser))
    }
}
