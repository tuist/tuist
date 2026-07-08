import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAutomation
import TuistCache
import TuistCI
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistGenerator
import TuistGit
import TuistServer
import TuistSupport
import TuistXCActivityLog
import TuistXcodeBuildProducts
import TuistXCResultService
import XcodeGraph
import XCResultParser
@testable import TuistKit
@testable import TuistTesting

struct TestServiceHostlessDerivedDataTests {
    @Test(.inTemporaryDirectory)
    func run_uses_passthrough_derived_data_as_hostless_isolation_base() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let harness = try TestServiceHarness(temporaryDirectory: temporaryDirectory)
        let graph = harness.mixedHostedAndHostlessGraph(temporaryDirectory: temporaryDirectory)
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")

        harness.stub(graph: graph)
        given(harness.xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(derivedDataPath: derivedDataPath))

        try await harness.run(
            path: temporaryDirectory,
            passthroughXcodeBuildArguments: ["-derivedDataPath", derivedDataPath.pathString]
        )

        #expect(harness.testedSchemes == ["App", "Feature"])
        #expect(harness.derivedDataPath(for: "App") == nil)
        #expect(
            harness.derivedDataPath(for: "Feature") == derivedDataPath
                .appending(components: "HostlessTests", "Feature")
        )
    }

    @Test(.inTemporaryDirectory)
    func run_without_building_does_not_isolate_hostless_schemes() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let harness = try TestServiceHarness(temporaryDirectory: temporaryDirectory)
        let graph = harness.mixedHostedAndHostlessGraph(temporaryDirectory: temporaryDirectory)
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")

        harness.stub(graph: graph)

        try await harness.run(
            path: temporaryDirectory,
            action: .testWithoutBuilding,
            derivedDataPath: derivedDataPath.pathString
        )

        #expect(harness.testedSchemes == ["App", "Feature"])
        #expect(harness.derivedDataPath(for: "App") == derivedDataPath)
        #expect(harness.derivedDataPath(for: "Feature") == derivedDataPath)
    }
}

private final class TestServiceHarness {
    let xcodeBuildArgumentParser = MockXcodeBuildArgumentParsing()

    private let generator = MockGenerating()
    private let generatorFactory = MockGeneratorFactorying()
    private let xcodebuildController = MockXcodeBuildControlling()
    private let buildGraphInspector = MockBuildGraphInspecting()
    private let simulatorController = MockSimulatorControlling()
    private let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
    private let configLoader = MockConfigLoading()
    private let cacheStorageFactory = MockCacheStorageFactorying()
    private let cacheStorage = MockCacheStoring()
    private let xcResultService = MockXCResultServicing()
    private let uploadResultBundleService = MockUploadResultBundleServicing()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let createTestService = MockCreateTestServicing()
    private let gitController = MockGitControlling()
    private let ciController = MockCIControlling()
    private let testQuarantineService = MockTestQuarantineServicing()
    private let testCaseListService = MockTestCaseListServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let shardPlanService = MockShardPlanServicing()
    private let shardMatrixOutputService = MockShardMatrixOutputServicing()
    private let shardService = MockShardServicing()
    private let xcActivityLogController = MockXCActivityLogControlling()
    private let uploadBuildRunService = MockUploadBuildRunServicing()
    private let runMetadataStorage = RunMetadataStorage()
    private let testCallCaptures: TestCallCaptures
    private let subject: TestService

    var testedSchemes: [String] {
        testCallCaptures.testedSchemes
    }

    func derivedDataPath(for scheme: String) -> AbsolutePath? {
        testCallCaptures.derivedDataPath(for: scheme)
    }

    init(temporaryDirectory: AbsolutePath) throws {
        let testCallCaptures = TestCallCaptures()
        self.testCallCaptures = testCallCaptures

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
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(cacheStorage)
        given(cacheStorage)
            .store(.any, cacheCategory: .any)
            .willReturn([])
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory.appending(component: "runs"))
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])
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
        given(simulatorController)
            .findAvailableDevice(platform: .any, version: .any, minVersion: .any, deviceName: .any)
            .willReturn(.test())
        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(destination: nil))
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(temporaryDirectory.appending(component: "DefaultDerivedData"))
        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willReturn(nil)
        given(xcResultService)
            .parseTestStatuses(path: .any)
            .willReturn(TestResultStatuses(testCases: []))
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
        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(URL(string: "https://tuist.dev")!)
        given(shardMatrixOutputService)
            .output(.any)
            .willReturn()
        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
            .willReturn(nil)
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
            .willProduce { _, scheme, _, _, _, _, derivedDataPath, _, _, _, _, _, _, _ in
                testCallCaptures.testedSchemes.append(scheme)
                testCallCaptures.derivedDataPathCaptures.append((scheme: scheme, derivedDataPath: derivedDataPath))
            }

        subject = TestService(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            xcodebuildController: xcodebuildController,
            buildGraphInspector: buildGraphInspector,
            simulatorController: simulatorController,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            configLoader: configLoader,
            xcResultService: xcResultService,
            xcodeBuildArgumentParser: xcodeBuildArgumentParser,
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
    }

    func stub(graph: MixedHostedAndHostlessGraph) {
        given(generator)
            .generateWithGraph(path: .any, options: .any)
            .willProduce { path, _ in (path, graph.graph, MapperEnvironment()) }
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn([graph.appScheme, graph.featureScheme, graph.workspaceScheme])
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([graph.workspaceScheme])
    }

    func run(
        path: AbsolutePath,
        action: XcodeBuildTestAction = .test,
        derivedDataPath: String? = nil,
        passthroughXcodeBuildArguments: [String] = []
    ) async throws {
        try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
            try await subject.run(
                runId: "run-id",
                schemeName: nil,
                clean: false,
                noUpload: false,
                configuration: nil,
                path: path,
                deviceName: nil,
                platform: nil,
                osVersion: nil,
                action: action,
                rosetta: false,
                skipUITests: false,
                skipUnitTests: false,
                resultBundlePath: nil,
                derivedDataPath: derivedDataPath,
                retryCount: 0,
                testTargets: [],
                skipTestTargets: [],
                testPlanConfiguration: nil,
                validateTestTargetsParameters: false,
                ignoreBinaryCache: false,
                ignoreSelectiveTesting: false,
                generateOnly: false,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                skipQuarantine: false,
                shardReference: nil,
                shardGranularity: .module,
                shardMin: nil,
                shardMax: nil,
                shardTotal: nil,
                shardMaxDuration: nil,
                shardIndex: nil,
                shardSkipUpload: false,
                shardArchivePath: nil,
                mode: .local
            )
        }
    }

    func mixedHostedAndHostlessGraph(temporaryDirectory: AbsolutePath) -> MixedHostedAndHostlessGraph {
        let appProjectPath = temporaryDirectory.appending(component: "App")
        let featureProjectPath = temporaryDirectory.appending(component: "Feature")
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let featureTests = Target.test(name: "FeatureTests", product: .unitTests)
        let appTestsReference = TargetReference(projectPath: appProjectPath, name: appTests.name)
        let featureTestsReference = TargetReference(projectPath: featureProjectPath, name: featureTests.name)
        let appScheme = Scheme.test(
            name: "App",
            testAction: .test(targets: [.test(target: appTestsReference)])
        )
        let featureScheme = Scheme.test(
            name: "Feature",
            testAction: .test(targets: [.test(target: featureTestsReference)])
        )
        let workspaceScheme = Scheme.test(
            name: "Sample-Workspace",
            testAction: .test(
                targets: [
                    .test(target: appTestsReference),
                    .test(target: featureTestsReference),
                ]
            )
        )
        let appProject = Project.test(
            path: appProjectPath,
            targets: [app, appTests],
            schemes: [appScheme]
        )
        let featureProject = Project.test(
            path: featureProjectPath,
            targets: [feature, featureTests],
            schemes: [featureScheme]
        )
        let graph = Graph.test(
            workspace: .test(
                name: "Sample",
                projects: [appProjectPath, featureProjectPath],
                schemes: [workspaceScheme]
            ),
            projects: [
                appProjectPath: appProject,
                featureProjectPath: featureProject,
            ],
            dependencies: [
                .target(name: appTests.name, path: appProjectPath): [
                    .target(name: app.name, path: appProjectPath),
                ],
                .target(name: featureTests.name, path: featureProjectPath): [
                    .target(name: feature.name, path: featureProjectPath),
                ],
            ]
        )

        return MixedHostedAndHostlessGraph(
            graph: graph,
            appScheme: appScheme,
            featureScheme: featureScheme,
            workspaceScheme: workspaceScheme
        )
    }
}

private final class TestCallCaptures {
    var testedSchemes: [String] = []
    var derivedDataPathCaptures: [(scheme: String, derivedDataPath: AbsolutePath?)] = []

    func derivedDataPath(for scheme: String) -> AbsolutePath? {
        derivedDataPathCaptures.first { $0.scheme == scheme }?.derivedDataPath ?? nil
    }
}

private struct MixedHostedAndHostlessGraph {
    let graph: Graph
    let appScheme: Scheme
    let featureScheme: Scheme
    let workspaceScheme: Scheme
}
