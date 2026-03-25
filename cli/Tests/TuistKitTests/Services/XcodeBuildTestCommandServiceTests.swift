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
import TuistSupport
import TuistTesting
import TuistUniqueIDGenerator
import TuistRootDirectoryLocator
import TuistXCActivityLog
import TuistXCResultService
import XcodeGraph
import protocol XcodeGraphMapper.XcodeGraphMapping

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
    private let subject: XcodeBuildTestCommandService

    init() {
        given(testQuarantineService)
            .quarantinedTests(config: .any, skipQuarantine: .any)
            .willReturn([])
        given(testQuarantineService)
            .markQuarantinedTests(testSummary: .any, quarantinedTests: .any)
            .willProduce { summary, _ in summary }
        given(testQuarantineService)
            .onlyQuarantinedTestsFailed(testSummary: .any)
            .willReturn(false)
        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willReturn(nil)
        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(nil)

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
            testQuarantineService: testQuarantineService
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
        verify(xcodeBuildController)
            .run(arguments: .any)
            .called(1)

        let expectedResultBundlePath = temporaryDirectory.appending(components: "cache", uniqueID)
        await #expect(RunMetadataStorage.current.resultBundlePath == expectedResultBundlePath)
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

        // Then
        verify(xcodeBuildController)
            .run(
                arguments: .value([
                    "test",
                    "-scheme", "MyAppTests",
                    "-resultBundlePath", resultBundlePath.pathString,
                ])
            )
            .called(1)

        await #expect(RunMetadataStorage.current.resultBundlePath == resultBundlePath)
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
                .willReturn(.test(fullHandle: "tuist/tuist"))

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
                .uploadResultBundle(
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
                .uploadResultBundle(
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
}

@Mockable
protocol XcodeGraphMapping: XcodeGraphMapper.XcodeGraphMapping {
    func map(at path: AbsolutePath) async throws -> Graph
}
