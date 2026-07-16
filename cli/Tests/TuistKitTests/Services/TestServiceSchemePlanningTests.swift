import FileSystem
import FileSystemTesting
import Mockable
import Path
import Testing
import TuistAutomation
import TuistCache
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistGenerator
import TuistServer
import TuistXcodeBuildProducts
import XcodeGraph

@testable import TuistKit
@testable import TuistTesting

@Suite
struct TestServiceSchemePlanningTests {
    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func run_partitions_hosted_and_hostless_tests_without_overlapping_schemes() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scenario = SchemePlanningScenario(rootDirectory: temporaryDirectory)
        let fixture = TestServiceSchemePlanningFixture(scenario: scenario)
        let resultBundlePath = temporaryDirectory.appending(component: "result.xcresult")

        try await fixture.run(path: temporaryDirectory, resultBundlePath: resultBundlePath)

        #expect(fixture.testRuns == [
            CapturedTestRun(
                scheme: "Sample-Workspace",
                testTargets: [
                    try TestIdentifier(target: "AppSnapshotTests"),
                    try TestIdentifier(target: "AppTests"),
                ],
                resultBundlePath: temporaryDirectory.appending(component: "result-Sample-Workspace.xcresult")
            ),
            CapturedTestRun(
                scheme: "Feature",
                testTargets: [try TestIdentifier(target: "FeatureTests")],
                resultBundlePath: temporaryDirectory.appending(component: "result-Feature.xcresult")
            ),
            CapturedTestRun(
                scheme: "Sample-Workspace",
                testTargets: [try TestIdentifier(target: "OrphanTests")],
                resultBundlePath: temporaryDirectory.appending(
                    component: "result-Sample-Workspace-Hostless.xcresult"
                )
            ),
        ])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func run_excludes_passthrough_skips_from_scheme_runs_and_hashes() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scenario = SchemePlanningScenario(rootDirectory: temporaryDirectory)
        let fixture = TestServiceSchemePlanningFixture(scenario: scenario)

        try await fixture.run(
            path: temporaryDirectory,
            passthroughXcodeBuildArguments: [
                "-skip-testing:AppSnapshotTests",
                "-skip-testing:FeatureTests",
            ]
        )

        #expect(fixture.testRuns == [
            CapturedTestRun(
                scheme: "Sample-Workspace",
                testTargets: [try TestIdentifier(target: "AppTests")],
                resultBundlePath: nil
            ),
            CapturedTestRun(
                scheme: "Sample-Workspace",
                testTargets: [try TestIdentifier(target: "OrphanTests")],
                resultBundlePath: nil
            ),
        ])
        verify(fixture.cacheStorage)
            .store(
                .value([CacheStorableItem(name: "AppTests", hash: "app-tests-hash"): []]),
                cacheCategory: .value(.selectiveTests)
            )
            .called(1)
        verify(fixture.cacheStorage)
            .store(
                .value([CacheStorableItem(name: "AppSnapshotTests", hash: "app-snapshot-tests-hash"): []]),
                cacheCategory: .value(.selectiveTests)
            )
            .called(0)
        verify(fixture.cacheStorage)
            .store(
                .value([CacheStorableItem(name: "FeatureTests", hash: "feature-tests-hash"): []]),
                cacheCategory: .value(.selectiveTests)
            )
            .called(0)
        verify(fixture.cacheStorage)
            .store(
                .value([CacheStorableItem(name: "OrphanTests", hash: "orphan-tests-hash"): []]),
                cacheCategory: .value(.selectiveTests)
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func run_with_explicit_test_target_only_runs_its_assigned_scheme() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let scenario = SchemePlanningScenario(rootDirectory: temporaryDirectory)
        let fixture = TestServiceSchemePlanningFixture(scenario: scenario)

        try await fixture.run(
            path: temporaryDirectory,
            testTargets: [try TestIdentifier(target: "FeatureTests")]
        )

        #expect(fixture.testRuns == [
            CapturedTestRun(
                scheme: "Feature",
                testTargets: [try TestIdentifier(target: "FeatureTests")],
                resultBundlePath: nil
            ),
        ])
    }
}

private struct SchemePlanningScenario {
    let graph: Graph
    let mapperEnvironment: MapperEnvironment
    let rootDirectory: AbsolutePath
    let testableSchemes: [Scheme]
    let workspaceScheme: Scheme

    init(rootDirectory: AbsolutePath) {
        self.rootDirectory = rootDirectory
        let appProjectPath = rootDirectory.appending(component: "App")
        let featureProjectPath = rootDirectory.appending(component: "Feature")
        let orphanProjectPath = rootDirectory.appending(component: "Orphan")
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let appSnapshotTests = Target.test(name: "AppSnapshotTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let featureTests = Target.test(name: "FeatureTests", product: .unitTests)
        let orphan = Target.test(name: "Orphan", product: .framework)
        let orphanTests = Target.test(name: "OrphanTests", product: .unitTests)
        let appTestsReference = TargetReference(projectPath: appProjectPath, name: appTests.name)
        let appSnapshotTestsReference = TargetReference(projectPath: appProjectPath, name: appSnapshotTests.name)
        let featureTestsReference = TargetReference(projectPath: featureProjectPath, name: featureTests.name)
        let orphanTestsReference = TargetReference(projectPath: orphanProjectPath, name: orphanTests.name)
        let appScheme = Scheme.test(
            name: "App",
            testAction: .test(
                targets: [
                    .test(target: appTestsReference),
                    .test(target: appSnapshotTestsReference),
                ]
            )
        )
        let featureScheme = Scheme.test(
            name: "Feature",
            testAction: .test(targets: [.test(target: featureTestsReference)])
        )
        let allModulesScheme = Scheme.test(
            name: "AllModules",
            testAction: .test(
                targets: [
                    .test(target: appTestsReference),
                    .test(target: appSnapshotTestsReference),
                    .test(target: featureTestsReference),
                ]
            )
        )
        workspaceScheme = Scheme.test(
            name: "Sample-Workspace",
            testAction: .test(
                targets: [
                    .test(target: appTestsReference),
                    .test(target: appSnapshotTestsReference),
                    .test(target: featureTestsReference),
                    .test(target: orphanTestsReference),
                ]
            )
        )
        let appProject = Project.test(
            path: appProjectPath,
            targets: [app, appTests, appSnapshotTests],
            schemes: [appScheme, allModulesScheme]
        )
        let featureProject = Project.test(
            path: featureProjectPath,
            targets: [feature, featureTests],
            schemes: [featureScheme]
        )
        let orphanProject = Project.test(
            path: orphanProjectPath,
            targets: [orphan, orphanTests]
        )
        let workspace = Workspace.test(
            name: "Sample",
            projects: [appProjectPath, featureProjectPath, orphanProjectPath],
            schemes: [workspaceScheme]
        )
        graph = Graph.test(
            workspace: workspace,
            projects: [
                appProjectPath: appProject,
                featureProjectPath: featureProject,
                orphanProjectPath: orphanProject,
            ],
            dependencies: [
                .target(name: appTests.name, path: appProjectPath): [
                    .target(name: app.name, path: appProjectPath),
                ],
                .target(name: appSnapshotTests.name, path: appProjectPath): [
                    .target(name: app.name, path: appProjectPath),
                ],
                .target(name: featureTests.name, path: featureProjectPath): [
                    .target(name: feature.name, path: featureProjectPath),
                ],
                .target(name: orphanTests.name, path: orphanProjectPath): [
                    .target(name: orphan.name, path: orphanProjectPath),
                ],
            ]
        )
        var mapperEnvironment = MapperEnvironment()
        mapperEnvironment.initialGraph = graph
        mapperEnvironment.targetTestHashes = [
            appProjectPath: [
                "AppSnapshotTests": "app-snapshot-tests-hash",
                "AppTests": "app-tests-hash",
            ],
            featureProjectPath: ["FeatureTests": "feature-tests-hash"],
            orphanProjectPath: ["OrphanTests": "orphan-tests-hash"],
        ]
        self.mapperEnvironment = mapperEnvironment
        testableSchemes = [allModulesScheme, appScheme, featureScheme, workspaceScheme]
    }
}

private struct CapturedTestRun: Equatable {
    let scheme: String
    let testTargets: [TestIdentifier]
    let resultBundlePath: AbsolutePath?
}

private final class TestRunCapture {
    var runs: [CapturedTestRun] = []
}

private struct TestServiceSchemePlanningFixture {
    let cacheStorage = MockCacheStoring()

    private let capture: TestRunCapture
    private let runMetadataStorage = RunMetadataStorage()
    private let subject: TestService

    var testRuns: [CapturedTestRun] {
        capture.runs
    }

    init(scenario: SchemePlanningScenario) {
        let capture = TestRunCapture()
        self.capture = capture
        let generator = MockGenerating()
        let generatorFactory = MockGeneratorFactorying()
        let cacheStorageFactory = MockCacheStorageFactorying()
        let xcodebuildController = MockXcodeBuildControlling()
        let buildGraphInspector = MockBuildGraphInspecting()
        let simulatorController = MockSimulatorControlling()
        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        let configLoader = MockConfigLoading()
        let xcodeBuildArgumentParser = MockXcodeBuildArgumentParsing()
        let derivedDataLocator = MockDerivedDataLocating()

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(project: .testGeneratedProject()))
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willReturn(cacheStorage)
        given(cacheStorage)
            .store(.any, cacheCategory: .any)
            .willReturn([])
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(scenario.rootDirectory)
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
                (path, scenario.graph, scenario.mapperEnvironment)
            }
        given(buildGraphInspector)
            .testableSchemes(graphTraverser: .any)
            .willReturn(scenario.testableSchemes)
        given(buildGraphInspector)
            .workspaceSchemes(graphTraverser: .any)
            .willReturn([scenario.workspaceScheme])
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
        given(buildGraphInspector)
            .buildArguments(project: .any, target: .any, configuration: .any, skipSigning: .any)
            .willReturn([])
        given(simulatorController)
            .findAvailableDevice(
                platform: .any,
                version: .any,
                minVersion: .any,
                deviceName: .any
            )
            .willReturn(.test())
        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(destination: nil))
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(scenario.rootDirectory.appending(component: "DerivedData"))
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
            .willProduce { _, scheme, _, _, _, _, _, resultBundlePath, _, _, testTargets, _, _, _ in
                capture.runs.append(
                    CapturedTestRun(
                        scheme: scheme,
                        testTargets: testTargets,
                        resultBundlePath: resultBundlePath
                    )
                )
            }

        subject = TestService(
            generatorFactory: generatorFactory,
            cacheStorageFactory: cacheStorageFactory,
            xcodebuildController: xcodebuildController,
            buildGraphInspector: buildGraphInspector,
            simulatorController: simulatorController,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            configLoader: configLoader,
            xcodeBuildArgumentParser: xcodeBuildArgumentParser,
            derivedDataLocator: derivedDataLocator
        )
    }

    func run(
        path: AbsolutePath,
        resultBundlePath: AbsolutePath? = nil,
        testTargets: [TestIdentifier] = [],
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
                action: .test,
                rosetta: false,
                skipUITests: false,
                skipUnitTests: false,
                resultBundlePath: resultBundlePath,
                derivedDataPath: nil,
                retryCount: 0,
                testTargets: testTargets,
                skipTestTargets: [],
                testPlanConfiguration: nil,
                ignoreBinaryCache: false,
                ignoreSelectiveTesting: false,
                generateOnly: false,
                passthroughXcodeBuildArguments: passthroughXcodeBuildArguments,
                mode: .local
            )
        }
    }
}
