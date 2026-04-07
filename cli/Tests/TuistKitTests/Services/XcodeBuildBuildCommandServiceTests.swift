import FileSystem
import Foundation
import Logging
import Mockable
import Path
import Testing
import TuistAutomation
import TuistConfigLoader
import TuistCore
import TuistLoader
import TuistSupport
import TuistTesting
import TuistUniqueIDGenerator
import TuistXCActivityLog

@testable import TuistKit

@Suite
struct XcodeBuildBuildCommandServiceTests {
    private let fileSystem = FileSystem()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let configLoader = MockConfigLoading()
    private let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
    private let uniqueIDGenerator = MockUniqueIDGenerating()
    private let xcodeBuildArgumentParser = MockXcodeBuildArgumentParsing()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let xcActivityLogController = MockXCActivityLogControlling()
    private let uploadBuildRunService = MockUploadBuildRunServicing()
    private let subject: XcodeBuildBuildCommandService

    init() {
        subject = XcodeBuildBuildCommandService(
            fileSystem: fileSystem,
            xcodeBuildController: xcodeBuildController,
            configLoader: configLoader,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            uniqueIDGenerator: uniqueIDGenerator,
            xcodeBuildArgumentParser: xcodeBuildArgumentParser,
            derivedDataLocator: derivedDataLocator,
            xcActivityLogController: xcActivityLogController,
            uploadBuildRunService: uploadBuildRunService
        )
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func runsXcodeBuildWithPassthroughArguments() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let arguments = ["-scheme", "MyApp"]
        let uniqueID = "unique-id-123"
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

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

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any)
            .willReturn(URL(string: "https://tuist.dev/test")!)

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
    func uploadsBuildRunWhenFullHandleConfigured() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let arguments = ["-scheme", "MyApp"]
        let uniqueID = "unique-id-123"
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

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

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any)
            .willReturn(URL(string: "https://tuist.dev/test")!)

        // When
        try await subject.run(passthroughXcodebuildArguments: arguments)

        // Then
        verify(uploadBuildRunService)
            .uploadBuildRun(
                activityLogPath: .value(activityLogFile.path),
                projectPath: .any,
                config: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func doesNotUploadBuildRunWhenNoFullHandle() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let arguments = ["-scheme", "MyApp"]
        let uniqueID = "unique-id-123"
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

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

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        // When
        try await subject.run(passthroughXcodebuildArguments: arguments)

        // Then
        verify(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func doesNotFailWhenUploadBuildRunFails() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        // Given
        let arguments = ["-scheme", "MyApp"]
        let uniqueID = "unique-id-123"
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataPath.appending(components: "Logs", "Build", "activity.xcactivitylog")
        let activityLogFile: XCActivityLogFile = .test(path: activityLogPath)

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

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any)
            .willProduce { _, _, _ in
                throw NSError(domain: "test", code: 1)
            }

        // When / Then - should not throw despite upload failure
        try await subject.run(passthroughXcodebuildArguments: arguments)
    }
}
