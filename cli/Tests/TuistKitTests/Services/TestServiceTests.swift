import Foundation
import Mockable
import Path
import TuistAutomation
import TuistCache
import TuistCI
import TuistCore
import TuistGit
import TuistLoader
import TuistServer
import TuistSupport
import TuistXCResultService
import XcodeGraph
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
    private var inspectResultBundleService: MockInspectResultBundleServicing!
    private var derivedDataLocator: MockDerivedDataLocating!
    private var createTestService: MockCreateTestServicing!
    private var gitController: MockGitControlling!
    private var ciController: MockCIControlling!

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
        inspectResultBundleService = .init()
        derivedDataLocator = .init()
        createTestService = .init()
        gitController = .init()
        ciController = .init()

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
            inspectResultBundleService: inspectResultBundleService,
            derivedDataLocator: derivedDataLocator,
            createTestService: createTestService,
            ciController: ciController
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
        inspectResultBundleService = nil
        derivedDataLocator = nil
        createTestService = nil
        gitController = nil
        ciController = nil
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
                destination: .value(.test(device: .test(name: "Test iPhone")))
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
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
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
        try fileHandler.touch(
            testsCacheTemporaryDirectory.path.appending(component: "A")
        )
        try fileHandler.touch(
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
            try fileHandler.touch(
                testsCacheTemporaryDirectory.path.appending(component: "A")
            )
            try fileHandler.touch(
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
                destination: .any
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
        try fileHandler.touch(
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
        //        XCTAssertFalse(
        //            fileHandler.exists(cacheDirectoriesProvider.cacheDirectory(for: .selectiveTests).appending(component: "A"))
        //        )
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

        try fileHandler.createFolder(runsCacheDirectory)

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
                        fullHandle: "tuist/tuist"
                    )
                )

            given(inspectResultBundleService)
                .inspectResultBundle(resultBundlePath: .any, projectDerivedDataDirectory: .any, config: .any)
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
                destination: .any
            )
            .willReturn(generator)
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
        passthroughXcodeBuildArguments: [String] = []
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
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments
            )
        }
    }
}
