import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Synchronization
import Testing
import TuistAutomation
import TuistCache
import TuistCI
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistGenerator
import TuistGit
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistKit

@Suite
struct TestServiceSkippedTests {
    enum EmptyScheme: CaseIterable {
        case removed, noTargets, noTestPlans, workspaceRemoved
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), arguments: EmptyScheme.allCases, [false, true])
    func uploads_report_when_selective_testing_skips_everything(
        emptyScheme: EmptyScheme,
        isSharding: Bool
    ) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let fixture = Fixture(path: path, emptyScheme: emptyScheme)

        try await fixture.run(path: path, action: isSharding ? .build : .test, isSharding: isSharding)

        fixture.expectReportUpload(count: 1)
        #expect(await RunMetadataStorage.current.testRunId == "skipped-test-id")
        verify(fixture.shardMatrixOutputService)
            .output(.matching { $0.shard_count == 0 && $0.shards.isEmpty })
            .called(isSharding ? 1 : 0)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), arguments: EmptyScheme.allCases)
    func standalone_build_does_not_upload_test_report(emptyScheme: EmptyScheme) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let fixture = Fixture(path: path, emptyScheme: emptyScheme)

        try await fixture.run(path: path, action: .build, isSharding: false)

        fixture.expectReportUpload(count: 0)
        #expect(await RunMetadataStorage.current.testRunId == nil)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func skipped_sharded_build_without_full_handle_still_outputs_empty_matrix() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let fixture = Fixture(path: path, emptyScheme: .removed, fullHandle: nil)

        try await fixture.run(path: path, action: .build, isSharding: true)

        fixture.expectReportUpload(count: 0)
        verify(fixture.shardMatrixOutputService)
            .output(.matching { $0.shard_count == 0 && $0.shards.isEmpty })
            .called(1)
    }

    private struct Fixture {
        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        let createTestService = MockCreateTestServicing()
        let subject: TestService
        let reports: ReportCapture
        let emptyScheme: EmptyScheme

        // swiftlint:disable:next function_body_length
        init(path: AbsolutePath, emptyScheme: EmptyScheme, fullHandle: String? = "tuist/tuist") {
            self.emptyScheme = emptyScheme
            let reports = ReportCapture()
            self.reports = reports
            let generator = MockGenerating()
            let generatorFactory = MockGeneratorFactorying()
            let cacheStorageFactory = MockCacheStorageFactorying()
            let configLoader = MockConfigLoading()
            let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
            let buildGraphInspector = MockBuildGraphInspecting()
            let xcodeBuildArgumentParser = MockXcodeBuildArgumentParsing()
            let xcodebuildController = MockXcodeBuildControlling()
            let gitController = MockGitControlling()
            let ciController = MockCIControlling()
            let serverEnvironmentService = MockServerEnvironmentServicing()
            let target = Target.test(name: "AppTests", product: .unitTests)
            let targetReference = TargetReference(projectPath: path, name: target.name)
            let testableTarget = TestableTarget.test(target: targetReference)
            let initialScheme = Scheme.test(
                name: "AppTests",
                testAction: .test(
                    targets: [testableTarget],
                    testPlans: emptyScheme == .noTestPlans ? [
                        TestPlan(
                            path: path.appending(component: "Tests.xctestplan"),
                            testTargets: [testableTarget],
                            isDefault: true
                        ),
                    ] : nil
                )
            )
            var mapperEnvironment = MapperEnvironment()
            mapperEnvironment.initialGraph = .test(
                workspace: .test(schemes: emptyScheme == .workspaceRemoved ? [initialScheme] : []),
                projects: [path: .test(path: path, targets: [target], schemes: [initialScheme])]
            )
            let schemes: [Scheme] = switch emptyScheme {
            case .removed, .workspaceRemoved: []
            case .noTargets: [.test(name: "AppTests", testAction: .test(targets: []))]
            case .noTestPlans: [.test(name: "AppTests", testAction: .test(targets: [], testPlans: []))]
            }
            let graph = Graph.test(projects: [path: .test(path: path, targets: [], schemes: schemes)])

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(project: .testGeneratedProject(), fullHandle: fullHandle))
            given(cacheStorageFactory)
                .cacheStorage(config: .any)
                .willReturn(MockCacheStoring())
            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.runs))
                .willReturn(path)
            given(xcodeBuildArgumentParser)
                .parse(.any)
                .willReturn(.test(destination: nil))
            given(generatorFactory)
                .testing(
                    config: .any, testPlan: .any, includedTargets: .any, excludedTargets: .any,
                    skipUITests: .any, skipUnitTests: .any, configuration: .any,
                    ignoreBinaryCache: .any, ignoreSelectiveTesting: .any, cacheStorage: .any,
                    destination: .any, schemeName: .any
                )
                .willReturn(generator)
            given(generator)
                .generateWithGraph(path: .any, options: .any)
                .willReturn((path, graph, mapperEnvironment))
            given(buildGraphInspector)
                .testableSchemes(graphTraverser: .any)
                .willReturn([])
            given(buildGraphInspector)
                .workspaceSchemes(graphTraverser: .any)
                .willProduce { $0.workspace.schemes }
            given(gitController)
                .isInGitRepository(workingDirectory: .any)
                .willReturn(true)
            given(gitController)
                .topLevelGitDirectory(workingDirectory: .any)
                .willReturn(path)
            given(gitController)
                .gitInfo(workingDirectory: .any)
                .willReturn(.test(ref: "refs/pull/12862/merge", sha: "current-commit"))
            given(ciController)
                .ciInfo()
                .willReturn(nil)
            given(xcodebuildController)
                .version()
                .willReturn(nil)
            given(serverEnvironmentService)
                .url(configServerURL: .any)
                .willReturn(URL(string: "https://tuist.dev")!)
            given(shardMatrixOutputService)
                .output(.any)
                .willReturn()
            given(createTestService)
                .createTest(
                    fullHandle: .any, serverURL: .any, id: .any, testSummary: .any,
                    buildRunId: .any, gitBranch: .any, gitCommitSHA: .any, gitRef: .any,
                    gitRemoteURLOrigin: .any, isCI: .any, modelIdentifier: .any,
                    macOSVersion: .any, xcodeVersion: .any, ciRunId: .any,
                    ciProjectHandle: .any, ciHost: .any, ciProvider: .any,
                    shardPlanId: .any, shardIndex: .any, onlyTestIdentifiers: .any, skipTestIdentifiers: .any
                )
                .willProduce { _, _, _, summary, _, _, commit, ref, _, _, _, _, _, _, _, _, _, planId, shardIndex, _, _ in
                    reports.append(Report(
                        scheme: summary.testPlanName,
                        passed: summary.status == .passed,
                        moduleCount: summary.testModules.count,
                        commit: commit,
                        ref: ref,
                        shardPlanId: planId,
                        shardIndex: shardIndex
                    ))
                    return .init(
                        duration: 0, id: "skipped-test-id", project_id: 1, test_case_runs: [],
                        _type: .test, url: "https://tuist.dev/tuist/tuist/tests/test-runs/skipped-test-id"
                    )
                }

            subject = TestService(
                generatorFactory: generatorFactory,
                cacheStorageFactory: cacheStorageFactory,
                xcodebuildController: xcodebuildController,
                buildGraphInspector: buildGraphInspector,
                cacheDirectoriesProvider: cacheDirectoriesProvider,
                configLoader: configLoader,
                xcodeBuildArgumentParser: xcodeBuildArgumentParser,
                gitController: gitController,
                createTestService: createTestService,
                serverEnvironmentService: serverEnvironmentService,
                ciController: ciController,
                clock: StubClock(),
                shardMatrixOutputService: shardMatrixOutputService
            )
        }

        func run(path: AbsolutePath, action: XcodeBuildTestAction, isSharding: Bool) async throws {
            try await subject.run(
                runId: "run-id", schemeName: emptyScheme == .workspaceRemoved ? nil : "AppTests",
                clean: false, noUpload: false,
                configuration: nil, path: path, deviceName: nil, platform: nil, osVersion: nil,
                action: action, rosetta: false, skipUITests: false, skipUnitTests: false,
                resultBundlePath: nil, derivedDataPath: nil, retryCount: 0,
                testTargets: [], skipTestTargets: [],
                testPlanConfiguration: emptyScheme == .noTestPlans ? TestPlanConfiguration(testPlan: "Tests") : nil,
                ignoreBinaryCache: false, ignoreSelectiveTesting: false, generateOnly: false,
                passthroughXcodeBuildArguments: [], skipQuarantine: true,
                shardTotal: isSharding ? 2 : nil,
                mode: .remote
            )
        }

        func expectReportUpload(count: Int) {
            let reports = reports.values
            #expect(reports.count == count)
            for report in reports {
                #expect(report == Report(
                    scheme: "AppTests", passed: true, moduleCount: 0,
                    commit: "current-commit", ref: "refs/pull/12862/merge",
                    shardPlanId: nil, shardIndex: nil
                ))
            }
        }
    }

    private struct Report: Equatable, Sendable {
        let scheme: String?
        let passed: Bool
        let moduleCount: Int
        let commit: String?
        let ref: String?
        let shardPlanId: String?
        let shardIndex: Int?
    }

    private final class ReportCapture: Sendable {
        private let storage = Mutex<[Report]>([])

        var values: [Report] {
            storage.withLock { $0 }
        }

        func append(_ report: Report) {
            storage.withLock { $0.append(report) }
        }
    }
}
