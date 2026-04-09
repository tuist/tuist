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
import TuistServer
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
    private let shardPlanService = MockShardPlanServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
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
            shardPlanService: shardPlanService,
            serverEnvironmentService: serverEnvironmentService,
            uploadBuildRunService: uploadBuildRunService
        )
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func runsXcodeBuildWithPassthroughArguments() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
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
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
            .willReturn(URL(string: "https://tuist.dev/test")!)

        try await subject.run(passthroughXcodebuildArguments: arguments)

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
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
            .willReturn(URL(string: "https://tuist.dev/test")!)

        try await subject.run(passthroughXcodebuildArguments: arguments)

        verify(uploadBuildRunService)
            .uploadBuildRun(
                activityLogPath: .value(activityLogFile.path),
                projectPath: .any,
                config: .any,
                scheme: .any,
                configuration: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func doesNotUploadBuildRunWhenNoFullHandle() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
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

        try await subject.run(passthroughXcodebuildArguments: arguments)

        verify(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func doesNotFailWhenUploadBuildRunFails() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
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
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any, scheme: .any, configuration: .any)
            .willProduce { _, _, _, _, _ in
                throw NSError(domain: "test", code: 1)
            }

        try await subject.run(passthroughXcodebuildArguments: arguments)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func passesShardArchivePathToShardPlanService() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "MyAppTests.xctestproducts")
        let shardArchivePath = temporaryDirectory.appending(components: "artifacts", "bundle.aar")
        let derivedDataPath = temporaryDirectory.appending(component: "DerivedData")
        let resultBundlePath = temporaryDirectory.appending(component: "build.xcresult")

        try await fileSystem.makeDirectory(at: testProductsPath)

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
            .willReturn(nil)

        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(URL(string: "https://tuist.dev")!)

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

        try await subject.run(
            passthroughXcodebuildArguments: [
                "build-for-testing",
                "-scheme", "MyAppTests",
                "-destination", "platform=iOS Simulator,name=iPhone 16",
                "-resultBundlePath", resultBundlePath.pathString,
                "-testProductsPath", testProductsPath.pathString,
            ],
            shardTotal: 2,
            shardArchivePath: shardArchivePath
        )

        verify(shardPlanService)
            .plan(
                xctestproductsPath: .value(testProductsPath),
                destination: .value("platform=iOS Simulator,name=iPhone 16"),
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
}
