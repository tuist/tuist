import FileSystem
import Foundation
import Logging
import Mockable
import Path
import Testing
import TuistAlert
import TuistAutomation
import TuistConfigLoader
import TuistCore
import TuistLoader
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import TuistTesting
import TuistUniqueIDGenerator
import TuistXCActivityLog
import TuistXcodeBuildProducts
import TuistXCResultService
import XcodeGraph
import protocol XcodeGraphMapper.XcodeGraphMapping
import XCResultParser

@testable import TuistKit

@Suite
struct XcodeBuildTestCommandServiceTests {
    private let fileSystem = FileSystem()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let configLoader = MockConfigLoading()
    private let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
    private let uniqueIDGenerator = MockUniqueIDGenerating()
    private let xcodeBuildArgumentParser = MockXcodeBuildArgumentParsing()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let xcActivityLogController = MockXCActivityLogControlling()
    private let uploadResultBundleService = MockUploadResultBundleServicing()
    private let xcResultService = MockXCResultServicing()
    private let rootDirectoryLocator = MockRootDirectoryLocating()
    private let testQuarantineService = MockTestQuarantineServicing()
    private let testCaseListService = MockTestCaseListServicing()
    private let shardService = MockShardServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let uploadBuildRunService = MockUploadBuildRunServicing()
    private let subject: XcodeBuildTestCommandService

    init() {
        given(testCaseListService)
            .listTestCases(fullHandle: .any, serverURL: .any, state: .any)
            .willReturn([])
        given(testQuarantineService)
            .markQuarantinedTests(testSummary: .any, quarantinedTests: .any)
            .willProduce { summary, _ in summary }
        given(testQuarantineService)
            .onlyQuarantinedTestsFailed(testSummary: .any)
            .willReturn(false)
        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(URL(string: "https://tuist.dev")!)
        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willReturn(nil)
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(nil)
        given(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
            .willReturn(URL(string: "https://tuist.dev/test")!)

        subject = XcodeBuildTestCommandService(
            fileSystem: fileSystem,
            xcodeBuildController: xcodeBuildController,
            configLoader: configLoader,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            uniqueIDGenerator: uniqueIDGenerator,
            xcodeBuildArgumentParser: xcodeBuildArgumentParser,
            derivedDataLocator: derivedDataLocator,
            xcActivityLogController: xcActivityLogController,
            uploadResultBundleService: uploadResultBundleService,
            xcResultService: xcResultService,
            rootDirectoryLocator: rootDirectoryLocator,
            testQuarantineService: testQuarantineService,
            testCaseListService: testCaseListService,
            shardService: shardService,
            serverEnvironmentService: serverEnvironmentService,
            uploadBuildRunService: uploadBuildRunService
        )
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func runsXcodeBuildWithPassthroughArguments() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let arguments = ["test", "-scheme", "MyAppTests"]
        let uniqueID = "unique-id-123"
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory.appending(component: "cache"))

        given(uniqueIDGenerator)
            .uniqueID()
            .willReturn(uniqueID)

        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(
                .test(
                    derivedDataPath: derivedDataPath
                )
            )

        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataPath), filter: .any)
            .willReturn(activityLogFile)

        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        // When
        try await subject.run(passthroughXcodebuildArguments: arguments)

        // Then
        let expectedResultBundlePath = temporaryDirectory.appending(components: "cache", uniqueID)
        verify(xcodeBuildController)
            .run(arguments: .value([
                "test",
                "-scheme", "MyAppTests",
                "-resultBundlePath", expectedResultBundlePath.pathString,
            ]))
            .called(1)

        await #expect(RunMetadataStorage.current.buildRunId == activityLogPath.basenameWithoutExt)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func preservesResultBundlePathWhenPassed() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let resultBundlePath = temporaryDirectory.appending(component: "custom.xcresult")
        let arguments = ["test", "-scheme", "MyAppTests", "-resultBundlePath", resultBundlePath.pathString]
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(
                .test(
                    derivedDataPath: derivedDataPath
                )
            )

        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataPath), filter: .any)
            .willReturn(activityLogFile)

        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        // When
        try await subject.run(passthroughXcodebuildArguments: arguments)

        // Then — the user-supplied `-resultBundlePath` arg is forwarded verbatim to
        // xcodebuild. `RunMetadataStorage.resultBundlePath` is intentionally left `nil`
        // for test flows: both local (test summary) and remote (uploadResultBundle)
        // own the bundle handoff without relying on `UploadAnalyticsService`.
        verify(xcodeBuildController)
            .run(
                arguments: .value([
                    "test",
                    "-scheme", "MyAppTests",
                    "-resultBundlePath", resultBundlePath.pathString,
                ])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func logsWarningWhenInspectResultBundleFails() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let alertController = AlertController()
        try await AlertController.$current.withValue(alertController) {
            // Given
            let resultBundlePath = temporaryDirectory.appending(component: "test.xcresult")
            try await fileSystem.makeDirectory(at: resultBundlePath)
            let arguments = ["test", "-scheme", "MyAppTests", "-resultBundlePath", resultBundlePath.pathString]
            let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
            let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
            let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test(fullHandle: "tuist/tuist", url: URL(string: "https://example.com")!))

            xcResultService.reset()
            given(xcResultService)
                .parse(path: .any, rootDirectory: .any)
                .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 0, testModules: []))

            given(xcodeBuildArgumentParser)
                .parse(.any)
                .willReturn(
                    .test(
                        derivedDataPath: derivedDataPath
                    )
                )

            given(xcActivityLogController)
                .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataPath), filter: .any)
                .willReturn(activityLogFile)

            given(xcodeBuildController)
                .run(arguments: .any)
                .willReturn()

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
            try await subject.run(passthroughXcodebuildArguments: arguments)

            // Then
            verify(uploadResultBundleService)
                .uploadTestSummary(
                    testSummary: .any,
                    projectDerivedDataDirectory: .any,
                    config: .any,
                    shardPlanId: .any,
                    shardIndex: .any
                )
                .called(1)
            let warnings = alertController.warnings()
            #expect(warnings.count == 1)
            #expect(warnings.first?.message.plain().contains("Failed to upload test results") == true)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func skipsResultBundleUploadWhenInspectModeIsOff() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let resultBundlePath = temporaryDirectory.appending(component: "test.xcresult")
        try await fileSystem.makeDirectory(at: resultBundlePath)
        let arguments = ["test", "-scheme", "MyAppTests", "-resultBundlePath", resultBundlePath.pathString]
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist", url: URL(string: "https://tuist.dev")!))

        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(derivedDataPath: derivedDataPath))

        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataPath), filter: .any)
            .willReturn(activityLogFile)

        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        // When
        try await subject.run(
            passthroughXcodebuildArguments: arguments,
            mode: .off
        )

        // Then
        verify(uploadResultBundleService)
            .uploadResultBundle(
                resultBundlePath: .any,
                config: .any,
                quarantinedTests: .any,
                buildRunId: .any,
                shardPlanId: .any,
                shardIndex: .any
            )
            .called(0)
        verify(uploadResultBundleService)
            .uploadTestSummary(
                testSummary: .any,
                projectDerivedDataDirectory: .any,
                config: .any,
                shardPlanId: .any,
                shardIndex: .any
            )
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func uploadsBuildRunWhenFullHandleConfigured() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let arguments = ["test", "-scheme", "MyAppTests"]
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist", url: URL(string: "https://example.com")!))

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory.appending(component: "cache"))

        given(uniqueIDGenerator)
            .uniqueID()
            .willReturn("unique-id-123")

        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(derivedDataPath: derivedDataPath))

        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataPath), filter: .any)
            .willReturn(activityLogFile)

        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        // When
        try await subject.run(passthroughXcodebuildArguments: arguments)

        // Then
        verify(uploadBuildRunService)
            .uploadBuildRun(
                activityLogPath: .value(activityLogPath),
                projectPath: .any,
                config: .any,
                scheme: .value("MyAppTests"),
                configuration: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func doesNotUploadBuildRunWhenNoFullHandle() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let arguments = ["test", "-scheme", "MyAppTests"]
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory.appending(component: "cache"))

        given(uniqueIDGenerator)
            .uniqueID()
            .willReturn("unique-id-123")

        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(derivedDataPath: derivedDataPath))

        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataPath), filter: .any)
            .willReturn(activityLogFile)

        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        // When
        try await subject.run(passthroughXcodebuildArguments: arguments)

        // Then
        verify(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func passesShardArchivePathToShardService() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let shardArchivePath = temporaryDirectory.appending(component: "bundle.aar")
        let testProductsPath = temporaryDirectory.appending(component: "Extracted.xctestproducts")
        let resultBundlePath = temporaryDirectory.appending(component: "test.xcresult")

        try await fileSystem.makeDirectory(at: testProductsPath)

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist", url: URL(string: "https://example.com")!))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(URL(string: "https://tuist.dev")!)

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
                    testProductsPath: testProductsPath,
                    xcTestRunPath: nil,
                    modules: ["AppTests"],
                    selectiveTestingGraph: nil
                )
            )

        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test())

        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        try await subject.run(
            passthroughXcodebuildArguments: [
                "test",
                "-scheme", "MyAppTests",
                "-resultBundlePath", resultBundlePath.pathString,
            ],
            shardIndex: 1,
            shardArchivePath: shardArchivePath
        )

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
}

@Mockable
protocol XcodeGraphMapping: XcodeGraphMapper.XcodeGraphMapping {
    func map(at path: AbsolutePath) async throws -> Graph
}
