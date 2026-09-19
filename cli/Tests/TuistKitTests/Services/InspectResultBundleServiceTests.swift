import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAlert
import TuistAutomation
import TuistCI
import TuistConfig
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistGit
import TuistLoader
import TuistRootDirectoryLocator
import TuistServer
import TuistSupport
import TuistTesting
import TuistXCActivityLog
import TuistXCResultService
import XcodeGraph
import XCResultParser

@testable import TuistKit

struct UploadResultBundleServiceTests {
    private let subject: UploadResultBundleService
    private let machineEnvironment = MockMachineEnvironmentRetrieving()
    private let createTestService = MockCreateTestServicing()
    private let createCrashReportService = MockCreateCrashReportServicing()
    private let createTestCaseRunAttachmentService = MockCreateTestCaseRunAttachmentServicing()
    private let dateService = MockDateServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let gitController = MockGitControlling()
    private let ciController = MockCIControlling()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let rootDirectoryLocator = MockRootDirectoryLocating()
    private let xcActivityLogController = MockXCActivityLogControlling()
    private let analyticsArtifactUploadService = MockAnalyticsArtifactUploadServicing()
    private let xcResultService = MockXCResultServicing()
    private let coverageUploadService = MockCoverageUploadServicing()
    private let fileSystem = FileSystem()

    init() throws {
        subject = UploadResultBundleService(
            machineEnvironment: machineEnvironment,
            createTestService: createTestService,
            coverageUploadService: coverageUploadService,
            createCrashReportService: createCrashReportService,
            createTestCaseRunAttachmentService: createTestCaseRunAttachmentService,
            dateService: dateService,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            ciController: ciController,
            xcodeBuildController: xcodeBuildController,
            rootDirectoryLocator: rootDirectoryLocator,
            xcActivityLogController: xcActivityLogController,
            analyticsArtifactUploadService: analyticsArtifactUploadService,
            fileSystem: fileSystem,
            xcResultService: xcResultService
        )

        given(machineEnvironment)
            .modelIdentifier()
            .willReturn("Mac15,3")

        given(machineEnvironment)
            .macOSVersion
            .willReturn("13.2.0")

        given(xcodeBuildController)
            .version()
            .willReturn(Version(16, 0, 0))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(try AbsolutePath(validating: "/tmp/project"))

        given(ciController)
            .ciInfo()
            .willReturn(nil)

        given(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                testSummary: .any,
                buildRunId: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .willReturn(
                Components.Schemas.RunsTest(
                    duration: 1000,
                    id: "test-id",
                    project_id: 1,
                    test_case_runs: [],
                    _type: .test,
                    url: "https://tuist.dev/tuist/tuist/runs/test-id"
                )
            )

        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .any, filter: .any)
            .willReturn(nil)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_createsTest() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()

        let testSummary = TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: [])

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(currentWorkingDirectory)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(
                .test(
                    ref: "git-ref",
                    branch: "main",
                    sha: "abc123",
                    remoteURLOrigin: "https://github.com/tuist/tuist"
                )
            )

        // When
        let result = try await subject.uploadTestSummary(
            testSummary: testSummary,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        // Then
        #expect(result.id == "test-id")
        #expect(result.url == "https://tuist.dev/tuist/tuist/runs/test-id")

        verify(createTestService)
            .createTest(
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
                id: .any,
                testSummary: .any,
                buildRunId: .value(nil),
                gitBranch: .value("main"),
                gitCommitSHA: .value("abc123"),
                gitRef: .value("git-ref"),
                gitRemoteURLOrigin: .value("https://github.com/tuist/tuist"),
                isCI: .value(false),
                modelIdentifier: .value("Mac15,3"),
                macOSVersion: .value("13.2.0"),
                xcodeVersion: .value("16.0.0"),
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_throwsWhenFullHandleMissing() async throws {
        let testSummary = TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: [])

        // When / Then
        await #expect(
            throws: UploadResultBundleServiceError.missingFullHandle
        ) {
            try await subject.uploadTestSummary(
                testSummary: testSummary,
                projectDerivedDataDirectory: nil,
                config: .test(fullHandle: nil),
                shardPlanId: nil,
                shardIndex: nil
            )
        }
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_usesWorkspacePathForGitInfo() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let workspacePath = try AbsolutePath(validating: "/workspace/path")
        mockedEnvironment.workspacePath = workspacePath

        let testSummary = TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: [])

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .value(workspacePath))
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .value(workspacePath))
            .willReturn(workspacePath)

        given(gitController)
            .gitInfo(workingDirectory: .value(workspacePath))
            .willReturn(.test())

        // When
        _ = try await subject.uploadTestSummary(
            testSummary: testSummary,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        // Then
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(workspacePath))
            .called(1)

        verify(gitController)
            .topLevelGitDirectory(workingDirectory: .value(workspacePath))
            .called(1)

        verify(gitController)
            .gitInfo(workingDirectory: .value(workspacePath))
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_passesBuildRunIdFromActivityLog() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let derivedDataDirectory = currentWorkingDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataDirectory.appending(components: "Logs", "Build", "build-123.xcactivitylog")

        let testSummary = TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: [])

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(currentWorkingDirectory)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        xcActivityLogController.reset()
        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataDirectory), filter: .any)
            .willReturn(
                XCActivityLogFile(
                    path: activityLogPath,
                    timeStoppedRecording: Date(),
                    signature: "Build"
                )
            )

        // When
        _ = try await subject.uploadTestSummary(
            testSummary: testSummary,
            projectDerivedDataDirectory: derivedDataDirectory,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        // Then
        verify(createTestService)
            .createTest(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                id: .any,
                testSummary: .any,
                buildRunId: .value("build-123"),
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_prefersRunMetadataStorageBuildRunIdOverActivityLog() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let derivedDataDirectory = currentWorkingDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataDirectory.appending(components: "Logs", "Build", "stale-build.xcactivitylog")

        let testSummary = TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: [])

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)
        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(currentWorkingDirectory)
        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        xcActivityLogController.reset()
        given(xcActivityLogController)
            .mostRecentActivityLogFile(projectDerivedDataDirectory: .value(derivedDataDirectory), filter: .any)
            .willReturn(
                XCActivityLogFile(
                    path: activityLogPath,
                    timeStoppedRecording: Date(),
                    signature: "Build"
                )
            )

        let storage = RunMetadataStorage()
        await storage.update(buildRunId: "snapshot-build-run")

        // When
        try await RunMetadataStorage.$current.withValue(storage) {
            _ = try await subject.uploadTestSummary(
                testSummary: testSummary,
                projectDerivedDataDirectory: derivedDataDirectory,
                config: .test(fullHandle: "tuist/tuist"),
                shardPlanId: nil,
                shardIndex: nil
            )
        }

        // Then — snapshot-restored buildRunId wins over the local activity log.
        verify(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                testSummary: .any,
                buildRunId: .value("snapshot-build-run"),
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_passesCIMetadata() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()

        let testSummary = TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: [])

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(currentWorkingDirectory)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(
                .test(
                    ref: "git-ref",
                    branch: "main",
                    sha: "abc123",
                    remoteURLOrigin: "https://github.com/tuist/tuist"
                )
            )

        ciController.reset()
        given(ciController)
            .ciInfo()
            .willReturn(
                .test(
                    provider: .github,
                    runId: "19683527895",
                    projectHandle: "tuist/tuist",
                    host: "github.com"
                )
            )

        // When
        _ = try await subject.uploadTestSummary(
            testSummary: testSummary,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        // Then
        verify(createTestService)
            .createTest(
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
                id: .any,
                testSummary: .any,
                buildRunId: .any,
                gitBranch: .value("main"),
                gitCommitSHA: .value("abc123"),
                gitRef: .value("git-ref"),
                gitRemoteURLOrigin: .value("https://github.com/tuist/tuist"),
                isCI: .value(false),
                modelIdentifier: .value("Mac15,3"),
                macOSVersion: .value("13.2.0"),
                xcodeVersion: .value("16.0.0"),
                ciRunId: .value("19683527895"),
                ciProjectHandle: .value("tuist/tuist"),
                ciHost: .value("github.com"),
                ciProvider: .value(.github),
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_handlesNilCIInfo() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()

        let testSummary = TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: [])

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(currentWorkingDirectory)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        ciController.reset()
        given(ciController)
            .ciInfo()
            .willReturn(nil)

        // When
        _ = try await subject.uploadTestSummary(
            testSummary: testSummary,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        // Then
        verify(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                testSummary: .any,
                buildRunId: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .value(nil),
                ciProjectHandle: .value(nil),
                ciHost: .value(nil),
                ciProvider: .value(nil),
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_uploadsAttachments() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()

        let crashFilePath = currentWorkingDirectory.appending(component: "crash.ips")
        let screenshotFilePath = currentWorkingDirectory.appending(component: "screenshot.png")

        let crashReport = CrashReport(
            exceptionType: "EXC_BAD_ACCESS",
            signal: "SIGSEGV",
            exceptionSubtype: "KERN_INVALID_ADDRESS",
            filePath: crashFilePath,
            triggeredThreadFrames: "frame #0"
        )

        let testCaseWithAttachments = TestCase(
            name: "test_example",
            testSuite: "ExampleTests",
            module: "AppTests",
            duration: 500,
            status: .failed,
            failures: [],
            crashReport: crashReport,
            attachments: [
                TestAttachment(filePath: screenshotFilePath, fileName: "screenshot.png", repetitionNumber: 2),
                TestAttachment(filePath: crashFilePath, fileName: "crash.ips", repetitionNumber: 2),
            ]
        )

        let testModule = TestModule(
            name: "AppTests",
            status: .failed,
            duration: 500,
            testSuites: [],
            testCases: [testCaseWithAttachments]
        )

        let testSummary = TestSummary(
            testPlanName: nil,
            status: .failed,
            duration: 500,
            testModules: [testModule]
        )

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(currentWorkingDirectory)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        createTestService.reset()
        given(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                testSummary: .any,
                buildRunId: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .willReturn(
                Components.Schemas.RunsTest(
                    duration: 500,
                    id: "test-id",
                    project_id: 1,
                    test_case_runs: [
                        .init(
                            id: "test-case-run-1",
                            module_name: "AppTests",
                            name: "test_example",
                            suite_name: "ExampleTests"
                        ),
                    ],
                    _type: .test,
                    url: "https://tuist.dev/tuist/tuist/runs/test-id"
                )
            )

        given(createTestCaseRunAttachmentService)
            .createAttachment(
                fullHandle: .any,
                serverURL: .any,
                testCaseRunId: .any,
                fileName: .any,
                filePath: .any,
                repetitionNumber: .any,
                testCaseRunArgumentId: .any
            )
            .willReturn("attachment-1")

        given(createCrashReportService)
            .createCrashReport(
                fullHandle: .any,
                serverURL: .any,
                crashReport: .any,
                testCaseRunId: .any,
                testCaseRunAttachmentId: .any
            )
            .willReturn()

        // When
        _ = try await subject.uploadTestSummary(
            testSummary: testSummary,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        // Then
        verify(createTestCaseRunAttachmentService)
            .createAttachment(
                fullHandle: .any,
                serverURL: .any,
                testCaseRunId: .any,
                fileName: .any,
                filePath: .any,
                repetitionNumber: .any,
                testCaseRunArgumentId: .any
            )
            .called(2)

        verify(createCrashReportService)
            .createCrashReport(
                fullHandle: .any,
                serverURL: .any,
                crashReport: .any,
                testCaseRunId: .any,
                testCaseRunAttachmentId: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_skipsAttachmentsWhenTestCaseHasNone() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()

        let testCaseWithoutAttachments = TestCase(
            name: "test_passing",
            testSuite: "PassingTests",
            module: "AppTests",
            duration: 100,
            status: .passed,
            failures: []
        )

        let testModule = TestModule(
            name: "AppTests",
            status: .passed,
            duration: 100,
            testSuites: [],
            testCases: [testCaseWithoutAttachments]
        )

        let testSummary = TestSummary(
            testPlanName: nil,
            status: .passed,
            duration: 100,
            testModules: [testModule]
        )

        gitController.reset()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(true)

        given(gitController)
            .topLevelGitDirectory(workingDirectory: .any)
            .willReturn(currentWorkingDirectory)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        createTestService.reset()
        given(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                testSummary: .any,
                buildRunId: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .willReturn(
                Components.Schemas.RunsTest(
                    duration: 100,
                    id: "test-id",
                    project_id: 1,
                    test_case_runs: [
                        .init(
                            id: "test-case-run-1",
                            module_name: "AppTests",
                            name: "test_passing",
                            suite_name: "PassingTests"
                        ),
                    ],
                    _type: .test,
                    url: "https://tuist.dev/tuist/tuist/runs/test-id"
                )
            )

        // When
        _ = try await subject.uploadTestSummary(
            testSummary: testSummary,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        // Then
        verify(createTestCaseRunAttachmentService)
            .createAttachment(
                fullHandle: .any,
                serverURL: .any,
                testCaseRunId: .any,
                fileName: .any,
                filePath: .any,
                repetitionNumber: .any,
                testCaseRunArgumentId: .any
            )
            .called(0)

        verify(createCrashReportService)
            .createCrashReport(
                fullHandle: .any,
                serverURL: .any,
                crashReport: .any,
                testCaseRunId: .any,
                testCaseRunAttachmentId: .any
            )
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadTestSummary_appliesTheExecutionModesRecordedInTheBundle() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        try TestExecutionModes(run: "parallel", targets: ["AppTests": "serial"])
            .write(toResultBundle: URL(fileURLWithPath: xcresultPath.pathString))

        _ = try await subject.uploadTestSummary(
            testSummary: TestSummary(
                testPlanName: nil,
                status: .passed,
                duration: 10,
                testModules: [TestModule(name: "AppTests", status: .passed, duration: 5, testSuites: [], testCases: [])]
            ),
            resultBundlePath: xcresultPath,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        verify(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                testSummary: .matching { $0.executionMode == "parallel" && $0.testModules.first?.executionMode == "serial" },
                buildRunId: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    // MARK: - uploadResultBundle (remote)

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadTestSummary_readsTheBundlesCoverageAgainstTheCheckout() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        let coverage = XcodeCoverageReport(partial: true, files: [])
        given(xcResultService)
            .coveredFilePaths(path: .value(xcresultPath))
            .willReturn(["/tmp/project/Sources/A.swift"])
        given(gitController)
            .sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any)
            .willReturn(["Sources/B.swift": "bbb", "Sources/A.swift": "aaa"])
        given(coverageUploadService)
            .prepare(resultBundlePath: .value(xcresultPath), manifest: .value(XcodeCoverageManifest(
                rootDirectories: ["/tmp/project", "/private/tmp/project"],
                partial: true,
                // B.swift is tracked but the run did not cover it.
                files: [XcodeCoverageSourceFile(path: "Sources/A.swift", gitBlobId: "aaa")]
            )), fullHandle: .any, serverURL: .any)
            .willReturn(PreparedCoverage(inline: coverage, upload: nil, testRunId: nil))

        _ = try await subject.uploadTestSummary(
            testSummary: TestSummary(testPlanName: nil, status: .passed, duration: 10, testModules: []),
            resultBundlePath: xcresultPath,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil,
            skipTestIdentifiers: ["AppTests/SlowTests"]
        )

        verify(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                testSummary: .matching { $0.coverage == coverage },
                buildRunId: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .any,
                shardIndex: .any,
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadTestSummary_doesNotMarkARunPartialForQuarantinedTestsAlone() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(["/tmp/project/Sources/A.swift"])
        given(gitController)
            .sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any)
            .willReturn(["Sources/A.swift": "aaa"])
        given(coverageUploadService)
            .prepare(resultBundlePath: .any, manifest: .matching { !$0.partial }, fullHandle: .any, serverURL: .any)
            .willReturn(PreparedCoverage(inline: XcodeCoverageReport(partial: false, files: []), upload: nil, testRunId: nil))

        let storage = RunMetadataStorage()
        await storage.update(skippedQuarantinedTestIdentifiers: ["AppTests/FlakyTests"])
        try await RunMetadataStorage.$current.withValue(storage) {
            _ = try await subject.uploadTestSummary(
                testSummary: TestSummary(testPlanName: nil, status: .passed, duration: 10, testModules: []),
                resultBundlePath: xcresultPath,
                projectDerivedDataDirectory: nil,
                config: .test(fullHandle: "tuist/tuist"),
                shardPlanId: nil,
                shardIndex: nil,
                skipTestIdentifiers: ["AppTests/FlakyTests"]
            )
        }

        verify(coverageUploadService)
            .prepare(resultBundlePath: .any, manifest: .matching { !$0.partial }, fullHandle: .any, serverURL: .any)
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadResultBundle_leavesCoverageOutWhenTheConfigTurnsItsUploadOff() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.writeText("", at: xcresultPath.appending(component: "Info.plist"))
        // A manifest an earlier upload of the same bundle left behind.
        try await fileSystem.writeText("{}", at: xcresultPath.appending(component: XcodeCoverageManifest.fileName))
        given(analyticsArtifactUploadService)
            .uploadResultBundle(.any, fullHandle: .any, commandEventId: .any, serverURL: .any)
            .willReturn()

        _ = try await subject.uploadResultBundle(
            resultBundlePath: xcresultPath,
            config: .test(
                fullHandle: "tuist/tuist",
                testInsights: TuistConfig.Tuist.TestInsights(coverage: .init(upload: false))
            ),
            quarantinedTests: [],
            shardPlanId: nil,
            shardIndex: nil
        )

        // Nothing is read from the bundle and nothing is added to it.
        verify(xcResultService).coveredFilePaths(path: .any).called(0)
        #expect(try await !fileSystem.exists(xcresultPath.appending(component: XcodeCoverageManifest.fileName)))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadsCoverage_letsTheEnvironmentVariableOverrideTheConfig() throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let enabled = TuistConfig.Tuist.test(fullHandle: "tuist/tuist")
        let disabled = TuistConfig.Tuist.test(
            fullHandle: "tuist/tuist",
            testInsights: TuistConfig.Tuist.TestInsights(coverage: .init(upload: false))
        )

        #expect(UploadResultBundleService.uploadsCoverage(config: enabled))
        #expect(!UploadResultBundleService.uploadsCoverage(config: disabled))

        Environment.mocked?.variables[UploadResultBundleService.coverageUploadVariable] = "0"
        #expect(!UploadResultBundleService.uploadsCoverage(config: enabled))

        Environment.mocked?.variables[UploadResultBundleService.coverageUploadVariable] = "1"
        #expect(UploadResultBundleService.uploadsCoverage(config: disabled))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadResultBundle_doesNoCoverageWorkWithoutTheFeatureFlag() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.writeText("", at: xcresultPath.appending(component: "Info.plist"))
        given(analyticsArtifactUploadService)
            .uploadResultBundle(.any, fullHandle: .any, commandEventId: .any, serverURL: .any)
            .willReturn()

        _ = try await subject.uploadResultBundle(
            resultBundlePath: xcresultPath,
            config: .test(fullHandle: "tuist/tuist"),
            quarantinedTests: [],
            shardPlanId: nil,
            shardIndex: nil
        )

        verify(xcResultService).coveredFilePaths(path: .any).called(0)
        #expect(try await !fileSystem.exists(xcresultPath.appending(component: XcodeCoverageManifest.fileName)))
    }

    @Test(.inTemporaryDirectory)
    func rootSpellings_includeThePrefixTheCompilerRecorded() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let checkout = temporaryDirectory.appending(component: "checkout")
        try await fileSystem.makeDirectory(at: checkout.appending(component: "Sources"))
        try await fileSystem.writeText("", at: checkout.appending(components: "Sources", "A.swift"))
        let link = temporaryDirectory.appending(component: "link")
        try await fileSystem.createSymbolicLink(from: link, to: checkout)

        // Git reports the canonical checkout; the build ran through the link.
        let got = UploadResultBundleService.rootSpellings(
            of: checkout,
            coveredFilePaths: [
                link.appending(components: "Sources", "A.swift").pathString,
                link.appending(components: "Sources", "Deleted.swift").pathString,
                "/elsewhere/Dependency.swift",
            ]
        )

        #expect(got.contains(link.pathString))
        #expect(got.contains(checkout.pathString))
        #expect(!got.contains("/elsewhere"))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadTestSummary_resolvesCoverageAgainstTheCheckoutTheProductsWereBuiltIn() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        let manifest = XcodeCoverageManifest(
            rootDirectories: ["/build-machine/checkout", "/tmp/project", "/private/tmp/project"],
            partial: false,
            files: [XcodeCoverageSourceFile(path: "Sources/A.swift", gitBlobId: "compiled")]
        )
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(["/build-machine/checkout/Sources/A.swift"])
        given(coverageUploadService)
            .prepare(resultBundlePath: .any, manifest: .value(manifest), fullHandle: .any, serverURL: .any)
            .willReturn(PreparedCoverage(inline: XcodeCoverageReport(partial: false, files: []), upload: nil, testRunId: nil))

        let storage = RunMetadataStorage()
        await storage.update(coverageBuildSources: CoverageBuildSources(
            rootDirectories: ["/build-machine/checkout"],
            files: ["Sources/A.swift": "compiled", "Sources/B.swift": "bbb"]
        ))
        try await RunMetadataStorage.$current.withValue(storage) {
            _ = try await subject.uploadTestSummary(
                testSummary: TestSummary(testPlanName: nil, status: .passed, duration: 10, testModules: []),
                resultBundlePath: xcresultPath,
                projectDerivedDataDirectory: nil,
                config: .test(fullHandle: "tuist/tuist"),
                shardPlanId: nil,
                shardIndex: nil
            )
        }

        verify(coverageUploadService)
            .prepare(resultBundlePath: .any, manifest: .value(manifest), fullHandle: .any, serverURL: .any)
            .called(1)
        // The current checkout may be at other content than what was compiled.
        verify(gitController)
            .sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), .withMockedDependencies())
    func uploadTestSummary_warnsWhenNoCoveredFileIsInTheCheckout() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(["/build-machine/checkout/Sources/A.swift"])
        given(gitController)
            .sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any)
            .willReturn(["Sources/A.swift": "aaa"])
        given(coverageUploadService)
            .prepare(resultBundlePath: .any, manifest: .matching { $0.files.isEmpty }, fullHandle: .any, serverURL: .any)
            .willReturn(PreparedCoverage(inline: XcodeCoverageReport(partial: false, files: []), upload: nil, testRunId: nil))

        _ = try await subject.uploadTestSummary(
            testSummary: TestSummary(testPlanName: nil, status: .passed, duration: 10, testModules: []),
            resultBundlePath: xcresultPath,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist"),
            shardPlanId: nil,
            shardIndex: nil
        )

        let warnings = AlertController.current.warnings()
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.plain().contains("None of the 1 files covered") == true)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadResultBundle_writesTheCoverageManifestIntoTheBundle() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.writeText("", at: xcresultPath.appending(component: "Info.plist"))
        let manifestPath = xcresultPath.appending(component: XcodeCoverageManifest.fileName)

        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(["/tmp/project/Sources/A.swift"])
        given(gitController)
            .sourceFileBlobIds(workingDirectory: .any, pathExtensions: .any)
            .willReturn(["Sources/A.swift": "aaa"])
        given(analyticsArtifactUploadService)
            .uploadResultBundle(.any, fullHandle: .any, commandEventId: .any, serverURL: .any)
            .willProduce { _, _, _, _ in
                // The manifest has to be in the bundle by the time it goes up.
                #expect(FileManager.default.fileExists(atPath: manifestPath.pathString))
            }

        _ = try await subject.uploadResultBundle(
            resultBundlePath: xcresultPath,
            config: .test(fullHandle: "tuist/tuist"),
            quarantinedTests: [],
            shardPlanId: nil,
            shardIndex: nil
        )

        let manifest = try JSONDecoder().decode(
            XcodeCoverageManifest.self,
            from: Data(try await fileSystem.readTextFile(at: manifestPath).utf8)
        )
        #expect(manifest == XcodeCoverageManifest(
            rootDirectories: ["/tmp/project", "/private/tmp/project"],
            partial: false,
            files: [XcodeCoverageSourceFile(path: "Sources/A.swift", gitBlobId: "aaa")]
        ))
        verify(coverageUploadService)
            .prepare(resultBundlePath: .any, manifest: .any, fullHandle: .any, serverURL: .any)
            .called(0)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadResultBundle_uploadsAndCreatesProcessingTest() async throws {
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(nil)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.writeText("", at: xcresultPath.appending(component: "Info.plist"))

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .any,
                fullHandle: .any,
                commandEventId: .any,
                serverURL: .any
            )
            .willReturn()

        let result = try await subject.uploadResultBundle(
            resultBundlePath: xcresultPath,
            config: .test(fullHandle: "tuist/tuist"),
            quarantinedTests: [],
            shardPlanId: nil,
            shardIndex: nil
        )

        #expect(result.id == "test-id")

        verify(analyticsArtifactUploadService)
            .uploadResultBundle(
                .any,
                fullHandle: .value("tuist/tuist"),
                commandEventId: .any,
                serverURL: .value(Constants.URLs.production)
            )
            .called(1)

        verify(createTestService)
            .createTest(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                id: .any,
                testSummary: .any,
                buildRunId: .value(nil),
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                shardPlanId: .value(nil),
                shardIndex: .value(nil),
                onlyTestIdentifiers: .any,
                skipTestIdentifiers: .any,
                stressNewTests: .any,
                gitHistory: .any,
                coverageUpload: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadResultBundle_writesQuarantinedTestsJSON() async throws {
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(nil)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.writeText("", at: xcresultPath.appending(component: "Info.plist"))

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .any,
                fullHandle: .any,
                commandEventId: .any,
                serverURL: .any
            )
            .willReturn()

        let quarantinedTests = [
            try TestIdentifier(target: "AppTests", class: "Suite", method: "testA()"),
            try TestIdentifier(target: "CoreTests"),
        ]

        _ = try await subject.uploadResultBundle(
            resultBundlePath: xcresultPath,
            config: .test(fullHandle: "tuist/tuist"),
            quarantinedTests: quarantinedTests,
            shardPlanId: nil,
            shardIndex: nil
        )

        let jsonPath = xcresultPath.appending(component: "quarantined_tests.json")
        #expect(try await fileSystem.exists(jsonPath))

        let data = try Data(contentsOf: jsonPath.url)
        let entries = try JSONDecoder().decode([[String: String?]].self, from: data)
        #expect(entries.count == 2)
        #expect(entries[0]["target"] == "AppTests")
        #expect(entries[0]["class"] == "Suite")
        #expect(entries[0]["method"] == "testA()")
        #expect(entries[1]["target"] == "CoreTests")
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadResultBundle_resolvesSymlinkBeforeUpload() async throws {
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(nil)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "result-bundle.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)
        try await fileSystem.writeText("", at: xcresultPath.appending(component: "Info.plist"))
        let symlinkPath = temporaryDirectory.appending(component: "result-bundle")
        try FileManager.default.createSymbolicLink(
            atPath: symlinkPath.pathString,
            withDestinationPath: xcresultPath.pathString
        )

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .any,
                fullHandle: .any,
                commandEventId: .any,
                serverURL: .any
            )
            .willReturn()

        _ = try await subject.uploadResultBundle(
            resultBundlePath: symlinkPath,
            config: .test(fullHandle: "tuist/tuist"),
            quarantinedTests: [],
            shardPlanId: nil,
            shardIndex: nil
        )

        verify(analyticsArtifactUploadService)
            .uploadResultBundle(
                .value(xcresultPath),
                fullHandle: .any,
                commandEventId: .any,
                serverURL: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func uploadResultBundle_throwsWhenFullHandleMissing() async throws {
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(nil)
        await #expect(
            throws: UploadResultBundleServiceError.missingFullHandle
        ) {
            try await subject.uploadResultBundle(
                resultBundlePath: try AbsolutePath(validating: "/tmp/Test.xcresult"),
                config: .test(fullHandle: nil),
                quarantinedTests: [],
                shardPlanId: nil,
                shardIndex: nil
            )
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadResultBundle_throwsWhenInfoPlistMissing() async throws {
        given(xcResultService)
            .coveredFilePaths(path: .any)
            .willReturn(nil)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcresultPath = temporaryDirectory.appending(component: "Test.xcresult")
        try await fileSystem.makeDirectory(at: xcresultPath)

        await #expect(
            throws: UploadResultBundleServiceError.bundleMissingInfoPlist(xcresultPath)
        ) {
            try await subject.uploadResultBundle(
                resultBundlePath: xcresultPath,
                config: .test(fullHandle: "tuist/tuist"),
                quarantinedTests: [],
                shardPlanId: nil,
                shardIndex: nil
            )
        }

        verify(analyticsArtifactUploadService)
            .uploadResultBundle(
                .any,
                fullHandle: .any,
                commandEventId: .any,
                serverURL: .any
            )
            .called(0)
    }
}
