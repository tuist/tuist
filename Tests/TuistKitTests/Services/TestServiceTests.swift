import Foundation
import MockableTest
import TSCBasic
import TuistAutomation
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistSupport
import XCTest

@testable import TuistAutomationTesting
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class TestServiceTests: TuistUnitTestCase {
    private var subject: TestService!
    private var generator: MockGenerator!
    private var generatorFactory: MockGeneratorFactorying!
    private var xcodebuildController: MockXcodeBuildController!
    private var buildGraphInspector: MockBuildGraphInspector!
    private var simulatorController: MockSimulatorController!
    private var contentHasher: MockContentHasher!
    private var testsCacheTemporaryDirectory: TemporaryDirectory!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var configLoader: MockConfigLoading!

    override func setUpWithError() throws {
        try super.setUpWithError()
        generator = .init()
        xcodebuildController = .init()
        buildGraphInspector = .init()
        simulatorController = .init()
        contentHasher = .init()
        testsCacheTemporaryDirectory = try TemporaryDirectory(removeTreeOnDeinit: true)
        generatorFactory = .init()
        let mockCacheDirectoriesProvider = MockCacheDirectoriesProviding()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider
        let cacheDirectoryProviderFactory = MockCacheDirectoriesProviderFactoring()
        given(cacheDirectoryProviderFactory)
            .cacheDirectories()
            .willReturn(mockCacheDirectoriesProvider)

        let runsCacheDirectory = try temporaryPath()
        given(mockCacheDirectoriesProvider)
            .tuistCacheDirectory(for: .value(.runs))
            .willReturn(runsCacheDirectory)

        configLoader = .init()

        contentHasher.hashStub = { _ in
            "hash"
        }

        subject = TestService(
            generatorFactory: generatorFactory,
            xcodebuildController: xcodebuildController,
            buildGraphInspector: buildGraphInspector,
            simulatorController: simulatorController,
            contentHasher: contentHasher,
            cacheDirectoryProviderFactory: cacheDirectoryProviderFactory,
            configLoader: configLoader
        )
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
        var generatedPath: AbsolutePath?
        generator.generateWithGraphStub = {
            generatedPath = $0
            return ($0, Graph.test())
        }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        // When
        try? await subject.testRun(
            path: path
        )

        // Then
        XCTAssertEqual(generatedPath, path)
    }

    func test_run_tests_wtih_specified_arch() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "App-Workspace"),
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.testableTargetStub = { scheme, _, _, _, _ in
            GraphTarget.test(
                target: Target.test(
                    name: scheme.name
                )
            )
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedRosetta: Bool?
        xcodebuildController.testStub = { _, _, _, _, rosetta, _, _, _, _, _, _, _, _ in
            testedRosetta = rosetta
        }

        // When
        try await subject.testRun(
            schemeName: "TestScheme",
            path: try temporaryPath(),
            rosetta: true
        )

        // Then
        XCTAssertEqual(testedRosetta, true)
    }

    func test_run_tests_for_only_specified_scheme() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "App-Workspace"),
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.testableTargetStub = { scheme, _, _, _, _ in
            GraphTarget.test(
                target: Target.test(
                    name: scheme.name
                )
            )
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
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
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
                Scheme.test(name: "ProjectSchemeTwo"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
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
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
                Scheme.test(name: "ProjectSchemeTwo"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
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

    func test_run_tests_with_skipped_targets() async throws {
        // Given
        given(generatorFactory)
            .testing(
                config: .any,
                testsCacheDirectory: .any,
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
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOneTests"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
            testedSchemes.append(scheme)
        }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOneTests",
            path: try temporaryPath(),
            skipTestTargets: [.init(target: "ProjectSchemeOnTests", class: "TestClass")]
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
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testErrorStub = NSError.test()
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
            testedSchemes.append(scheme)
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
        buildGraphInspector.workspaceSchemesStub = { _ in
            []
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
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

        xcodebuildController.testStub = { _, _, _, _, _, _, gotResourceBundlePath, _, _, _, _, _, _ in
            resourceBundlePath = gotResourceBundlePath
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
            ]
        }

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
            .tuistCacheDirectory(for: .runs)
            .appending(components: "run-id", Constants.resultBundleName)

        xcodebuildController.testStub = { _, _, _, _, _, _, gotResourceBundlePath, _, _, _, _, _, _ in
            resultBundlePath = gotResourceBundlePath
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
            ]
        }
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    cloud: .test()
                )
            )

        let runsCacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .tuistCacheDirectory(for: .value(.runs))
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

        xcodebuildController.testStub = { _, _, _, _, _, _, gotResourceBundlePath, _, _, _, _, _, _ in
            resourceBundlePath = gotResourceBundlePath
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectScheme"),
                Scheme.test(name: "ProjectScheme2"),
            ]
        }

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
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }

        var passedRetryCount = 0
        xcodebuildController.testStub = { _, _, _, _, _, _, _, _, retryCount, _, _, _, _ in
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
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "TestScheme"),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }

        var passedRetryCount = -1
        xcodebuildController.testStub = { _, _, _, _, _, _, _, _, retryCount, _, _, _, _ in
            passedRetryCount = retryCount
        }

        // When
        try await subject.testRun(
            schemeName: "ProjectSchemeOne",
            path: try temporaryPath()
        )

        // Then
        XCTAssertEqual(passedRetryCount, 0)
    }

    func test_run_test_plan_success() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        let testPlan = "TestPlan"
        let testPlanPath = try AbsolutePath(validating: "/testPlan/\(testPlan)")
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "App-Workspace"),
                Scheme.test(
                    name: "TestScheme",
                    testAction: .test(
                        testPlans: [.init(path: testPlanPath, testTargets: [], isDefault: true)]
                    )
                ),
            ]
        }
        var passedTestPlan: String?
        buildGraphInspector.testableTargetStub = { scheme, testPlan, _, _, _ in
            passedTestPlan = testPlan
            return GraphTarget.test(
                target: Target.test(
                    name: scheme.name
                )
            )
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        var testedSchemes: [String] = []
        xcodebuildController.testStub = { _, scheme, _, _, _, _, _, _, _, _, _, _, _ in
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
        XCTAssertEqual(passedTestPlan, testPlan)
    }

    func test_run_test_plan_failure() async throws {
        // Given
        givenGenerator()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        let testPlan = "TestPlan"
        let testPlanPath = try AbsolutePath(validating: "/testPlan/\(testPlan)")
        buildGraphInspector.testableSchemesStub = { _ in
            [
                Scheme.test(name: "App-Workspace"),
                Scheme.test(
                    name: "TestScheme",
                    testAction: .test(
                        testPlans: [.init(path: testPlanPath, testTargets: [], isDefault: true)]
                    )
                ),
            ]
        }
        buildGraphInspector.workspaceSchemesStub = { _ in
            [
                Scheme.test(name: "ProjectSchemeOne"),
            ]
        }
        generator.generateWithGraphStub = { path in
            (path, Graph.test())
        }
        xcodebuildController.testStub = { _, _, _, _, _, _, _, _, _, _, _, _, _ in }

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
                testsCacheDirectory: .any,
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
