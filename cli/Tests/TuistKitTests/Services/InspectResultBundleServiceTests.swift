import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAutomation
import TuistCI
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
    private let fileSystem = FileSystem()

    init() throws {
        subject = UploadResultBundleService(
            machineEnvironment: machineEnvironment,
            createTestService: createTestService,
            createCrashReportService: createCrashReportService,
            createTestCaseRunAttachmentService: createTestCaseRunAttachmentService,
            dateService: dateService,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            ciController: ciController,
            xcodeBuildController: xcodeBuildController,
            rootDirectoryLocator: rootDirectoryLocator,
            xcActivityLogController: xcActivityLogController,
            fileSystem: fileSystem
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
                shardIndex: .any
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
        let result = try await subject.uploadResultBundle(
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
                shardIndex: .any
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
            try await subject.uploadResultBundle(
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
        _ = try await subject.uploadResultBundle(
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
        _ = try await subject.uploadResultBundle(
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
                shardIndex: .any
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
        _ = try await subject.uploadResultBundle(
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
                shardIndex: .any
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
        _ = try await subject.uploadResultBundle(
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
                shardIndex: .any
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
                shardIndex: .any
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
                repetitionNumber: .any
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
        _ = try await subject.uploadResultBundle(
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
                repetitionNumber: .any
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
                shardIndex: .any
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
        _ = try await subject.uploadResultBundle(
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
                repetitionNumber: .any
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
}
