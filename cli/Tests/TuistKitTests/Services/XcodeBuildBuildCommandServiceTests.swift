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
import TuistServer
import TuistSupport
import TuistTesting
import TuistUniqueIDGenerator
import TuistXCActivityLog
import TuistXcodeBuildProducts
@testable import TuistKit

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
    private let casProxyFailureService = MockCASProxyFailureServicing()
    private let subject: XcodeBuildBuildCommandService

    init() {
        given(casProxyFailureService)
            .failure(since: .any)
            .willReturn(nil)

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
            uploadBuildRunService: uploadBuildRunService,
            casProxyFailureService: casProxyFailureService
        )
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func warnsWhenTheCASProxyFailedDuringTheBuild() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        givenABuildWithoutActivityLog(in: temporaryDirectory)
        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()
        givenTheCASProxyFailed()

        try await subject.run(passthroughXcodebuildArguments: ["-scheme", "MyApp"])

        #expect(AlertController.current.warnings().map { $0.message.plain() } == [Self.casProxyFailureWarning])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func warnsWhenTheCASProxyFailedDuringABuildThatFailed() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        givenABuildWithoutActivityLog(in: temporaryDirectory)
        given(xcodeBuildController)
            .run(arguments: .any)
            .willThrow(TestError("xcodebuild failed"))
        givenTheCASProxyFailed()

        await #expect(throws: TestError.self) {
            try await subject.run(passthroughXcodebuildArguments: ["-scheme", "MyApp"])
        }

        #expect(AlertController.current.warnings().map { $0.message.plain() } == [Self.casProxyFailureWarning])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func doesNotWarnWhenTheCASProxyDidNotFail() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        givenABuildWithoutActivityLog(in: temporaryDirectory)
        given(xcodeBuildController)
            .run(arguments: .any)
            .willReturn()

        try await subject.run(passthroughXcodebuildArguments: ["-scheme", "MyApp"])

        #expect(AlertController.current.warnings().isEmpty)
        verify(casProxyFailureService)
            .failure(since: .any)
            .called(1)
    }

    private static let casProxyFailureWarning =
        "The Xcode cache proxy at /Users/tuist/.local/state/tuist/cas-proxy.sock failed during this build: proxy connect: No such file or directory (os error 2)"

    private func givenTheCASProxyFailed() {
        casProxyFailureService.reset()
        given(casProxyFailureService)
            .failure(since: .any)
            .willReturn(
                CASProxyFailure(
                    socket: "/Users/tuist/.local/state/tuist/cas-proxy.sock",
                    error: "proxy connect: No such file or directory (os error 2)"
                )
            )
    }

    private func givenABuildWithoutActivityLog(in temporaryDirectory: AbsolutePath) {
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory.appending(component: "cache"))
        given(uniqueIDGenerator)
            .uniqueID()
            .willReturn("unique-id")
        given(xcodeBuildArgumentParser)
            .parse(.any)
            .willReturn(.test(derivedDataPath: temporaryDirectory.appending(component: "DerivedData")))
        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
            .willReturn(nil)
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
            .willReturn(try #require(URL(string: "https://tuist.dev/test")))

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
            .willReturn(try #require(URL(string: "https://tuist.dev/test")))

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
            .willReturn(try #require(URL(string: "https://tuist.dev")))

        given(shardPlanService)
            .plan(
                xctestproductsPath: .any,
                projectPath: .any,
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
                    shards: [],
                    upload_url: "https://tuist.dev/api/projects/tuist/tuist/tests/shards/upload/start"
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
                projectPath: .any,
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
