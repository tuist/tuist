import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAutomation
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
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let rootDirectoryLocator = MockRootDirectoryLocating()

    init() throws {
        subject = InspectResultBundleService(
            machineEnvironment: machineEnvironment,
            createTestService: createTestService,
            xcResultService: xcResultService,
            dateService: dateService,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            xcodeBuildController: xcodeBuildController,
            rootDirectoryLocator: rootDirectoryLocator
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

        given(createTestService)
            .createTest(
                fullHandle: .any,
                serverURL: .any,
                testSummary: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                xcodeVersion: .any
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
                gitBranch: .value("main"),
                gitCommitSHA: .value("abc123"),
                gitRef: .value("git-ref"),
                gitRemoteURLOrigin: .value("https://github.com/tuist/tuist"),
                isCI: .value(false),
                modelIdentifier: .value("Mac15,3"),
                macOSVersion: .value("13.2.0"),
                xcodeVersion: .value("16.0.0")
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
}
