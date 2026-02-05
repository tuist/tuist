import FileSystem
import Foundation
import Logging
import Mockable
import Path
import Testing
import TuistAlert
import TuistAutomation
import TuistCore
import TuistLoader
import TuistSupport
import TuistTesting
import TuistUniqueIDGenerator
import TuistXCActivityLog
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
    private let inspectResultBundleService = MockInspectResultBundleServicing()
    private let subject: XcodeBuildTestCommandService

    init() {
        subject = XcodeBuildTestCommandService(
            fileSystem: fileSystem,
            xcodeBuildController: xcodeBuildController,
            configLoader: configLoader,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            uniqueIDGenerator: uniqueIDGenerator,
            xcodeBuildArgumentParser: xcodeBuildArgumentParser,
            derivedDataLocator: derivedDataLocator,
            xcActivityLogController: xcActivityLogController,
            inspectResultBundleService: inspectResultBundleService
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

            given(inspectResultBundleService)
                .inspectResultBundle(resultBundlePath: .any, projectDerivedDataDirectory: .any, config: .any)
                .willThrow(TestError("Inspect failed"))

            // When
            try await subject.run(passthroughXcodebuildArguments: arguments)

            // Then
            verify(inspectResultBundleService)
                .inspectResultBundle(resultBundlePath: .any, projectDerivedDataDirectory: .any, config: .any)
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
