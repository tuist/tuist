import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAutomation
import TuistCI
import TuistCore
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

struct InspectResultBundleServiceTests {
    private let subject: InspectResultBundleService
    private let machineEnvironment = MockMachineEnvironmentRetrieving()
    private let createTestService = MockCreateTestServicing()
    private let xcResultService = MockXCResultServicing()
    private let dateService = MockDateServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let gitController = MockGitControlling()
    private let ciController = MockCIControlling()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let rootDirectoryLocator = MockRootDirectoryLocating()
    private let xcActivityLogController = MockXCActivityLogControlling()

    init() throws {
        subject = InspectResultBundleService(
            machineEnvironment: machineEnvironment,
            createTestService: createTestService,
            xcResultService: xcResultService,
            dateService: dateService,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            ciController: ciController,
            xcodeBuildController: xcodeBuildController,
            rootDirectoryLocator: rootDirectoryLocator,
            xcActivityLogController: xcActivityLogController
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
                ciProvider: .any
            )
            .willReturn(
                Components.Schemas.RunsTest(
                    duration: 1000,
                    id: "test-id",
                    project_id: 1,
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
        let resultBundlePath = currentWorkingDirectory.appending(component: "Test.xcresult")

        given(xcResultService)
            .parse(path: .value(resultBundlePath), rootDirectory: .any)
            .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: []))

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
        let result = try await subject.inspectResultBundle(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist")
        )

        // Then
        #expect(result.id == "test-id")
        #expect(result.url == "https://tuist.dev/tuist/tuist/runs/test-id")

        verify(createTestService)
            .createTest(
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
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
                ciProvider: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_throwsWhenFullHandleMissing() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let resultBundlePath = currentWorkingDirectory.appending(component: "Test.xcresult")

        given(xcResultService)
            .parse(path: .value(resultBundlePath), rootDirectory: .any)
            .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: []))

        // When / Then
        await #expect(
            throws: InspectResultBundleServiceError.missingFullHandle
        ) {
            try await subject.inspectResultBundle(
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: nil,
                config: .test(fullHandle: nil)
            )
        }
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_throwsWhenInvocationRecordMissing() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let resultBundlePath = currentWorkingDirectory.appending(component: "Test.xcresult")

        given(xcResultService)
            .parse(path: .value(resultBundlePath), rootDirectory: .any)
            .willReturn(nil)

        // When / Then
        await #expect(
            throws: InspectResultBundleServiceError.missingInvocationRecord
        ) {
            try await subject.inspectResultBundle(
                resultBundlePath: resultBundlePath,
                projectDerivedDataDirectory: nil,
                config: .test(fullHandle: "tuist/tuist")
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
        let resultBundlePath = currentWorkingDirectory.appending(component: "Test.xcresult")

        given(xcResultService)
            .parse(path: .value(resultBundlePath), rootDirectory: .any)
            .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: []))

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
        _ = try await subject.inspectResultBundle(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist")
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
        let resultBundlePath = currentWorkingDirectory.appending(component: "Test.xcresult")
        let derivedDataDirectory = currentWorkingDirectory.appending(component: "DerivedData")
        let activityLogPath = derivedDataDirectory.appending(components: "Logs", "Build", "build-123.xcactivitylog")

        given(xcResultService)
            .parse(path: .value(resultBundlePath), rootDirectory: .any)
            .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: []))

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
        _ = try await subject.inspectResultBundle(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: derivedDataDirectory,
            config: .test(fullHandle: "tuist/tuist")
        )

        // Then
        verify(createTestService)
            .createTest(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
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
                ciProvider: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_passesCIMetadata() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let resultBundlePath = currentWorkingDirectory.appending(component: "Test.xcresult")

        given(xcResultService)
            .parse(path: .value(resultBundlePath), rootDirectory: .any)
            .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: []))

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
        _ = try await subject.inspectResultBundle(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist")
        )

        // Then
        verify(createTestService)
            .createTest(
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(Constants.URLs.production),
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
                ciProvider: .value(.github)
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func inspectResultBundle_handlesNilCIInfo() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let resultBundlePath = currentWorkingDirectory.appending(component: "Test.xcresult")

        given(xcResultService)
            .parse(path: .value(resultBundlePath), rootDirectory: .any)
            .willReturn(TestSummary(testPlanName: nil, status: .passed, duration: 100, testModules: []))

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
        _ = try await subject.inspectResultBundle(
            resultBundlePath: resultBundlePath,
            projectDerivedDataDirectory: nil,
            config: .test(fullHandle: "tuist/tuist")
        )

        // Then
        verify(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
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
                ciProvider: .value(nil)
            )
            .called(1)
    }
}
