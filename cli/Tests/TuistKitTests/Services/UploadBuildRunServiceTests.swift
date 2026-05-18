import FileSystem
import Foundation
import Mockable
import Testing
import TuistAutomation
import TuistCI
import TuistConfig
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGit
import TuistMachineMetrics
import TuistServer
import TuistSupport
import TuistTesting
import TuistXCActivityLog
import XcodeGraph

@testable import TuistKit

struct UploadBuildRunServiceTests {
    private let subject: UploadBuildRunService
    private let fileSystem = FileSystem()
    private let createBuildService = MockCreateBuildServicing()
    private let uploadBuildService = MockUploadBuildServicing()
    private let machineEnvironment = MockMachineEnvironmentRetrieving()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let gitController = MockGitControlling()
    private let ciController = MockCIControlling()

    init() throws {
        subject = UploadBuildRunService(
            fileSystem: fileSystem,
            machineEnvironment: machineEnvironment,
            xcodeBuildController: xcodeBuildController,
            createBuildService: createBuildService,
            uploadBuildService: uploadBuildService,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            ciController: ciController
        )

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(createBuildService)
            .createBuild(
                fullHandle: .any, serverURL: .any, id: .any, category: .any,
                configuration: .any, customMetadata: .any, duration: .any,
                files: .any, gitBranch: .any, gitCommitSHA: .any, gitRef: .any,
                gitRemoteURLOrigin: .any, isCI: .any, issues: .any,
                modelIdentifier: .any, macOSVersion: .any, scheme: .any,
                targets: .any, xcodeCacheUploadEnabled: .any, xcodeVersion: .any,
                status: .any, ciRunId: .any, ciProjectHandle: .any,
                ciHost: .any, ciProvider: .any, cacheableTasks: .any,
                casOutputs: .any, machineMetrics: .any
            )
            .willReturn(.test())

        given(uploadBuildService)
            .uploadBuild(buildId: .any, fullHandle: .any, serverURL: .any, filePath: .any)
            .willReturn(())

        given(machineEnvironment)
            .modelIdentifier()
            .willReturn("Mac15,3")

        given(machineEnvironment)
            .macOSVersion
            .willReturn("13.2.0")

        given(xcodeBuildController)
            .version()
            .willReturn(Version(16, 0, 0))

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        given(ciController)
            .ciInfo()
            .willReturn(.test())

        Matcher.register([XCActivityIssue].self)
        Matcher.register([XCActivityBuildFile].self)
        Matcher.register([XCActivityTarget].self)
        Matcher.register([MachineMetricSample].self)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uploadsAndCreatesBuild() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let activityLogPath = temporaryDirectory.appending(component: "test-uuid.xcactivitylog")
        try await fileSystem.writeText("fake", at: activityLogPath)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables["CONFIGURATION"] = "Debug"

        gitController.reset()
        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(
                .test(
                    ref: "git-ref",
                    branch: "branch",
                    sha: "sha",
                    remoteURLOrigin: "https://github.com/tuist/tuist"
                )
            )

        ciController.reset()
        given(ciController)
            .ciInfo()
            .willReturn(
                .test(
                    provider: .github,
                    runId: "123",
                    projectHandle: "test-project",
                    host: "github.com"
                )
            )

        let config = Tuist.test(fullHandle: "tuist/tuist")

        // When
        try await subject.uploadBuildRun(
            activityLogPath: activityLogPath,
            projectPath: projectPath,
            config: config,
            scheme: "App",
            configuration: "Debug"
        )

        // Then
        verify(uploadBuildService)
            .uploadBuild(
                buildId: .value("test-uuid"),
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                filePath: .any
            )
            .called(1)

        verify(createBuildService)
            .createBuild(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                id: .value("test-uuid"),
                category: .value(.incremental),
                configuration: .value("Debug"),
                customMetadata: .any,
                duration: .value(0),
                files: .value([]),
                gitBranch: .value("branch"),
                gitCommitSHA: .value("sha"),
                gitRef: .value("git-ref"),
                gitRemoteURLOrigin: .value("https://github.com/tuist/tuist"),
                isCI: .value(false),
                issues: .value([]),
                modelIdentifier: .value("Mac15,3"),
                macOSVersion: .value("13.2.0"),
                scheme: .any,
                targets: .value([]),
                xcodeCacheUploadEnabled: .any,
                xcodeVersion: .value("16.0.0"),
                status: .value(.processing),
                ciRunId: .value("123"),
                ciProjectHandle: .value("test-project"),
                ciHost: .value("github.com"),
                ciProvider: .value(.github),
                cacheableTasks: .value([]),
                casOutputs: .value([]),
                machineMetrics: .value([])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func throwsWhenNoFullHandle() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let activityLogPath = temporaryDirectory.appending(component: "test-uuid.xcactivitylog")
        try await fileSystem.writeText("fake", at: activityLogPath)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let config = Tuist.test(fullHandle: nil)

        await #expect(throws: UploadBuildRunServiceError.missingFullHandle) {
            try await subject.uploadBuildRun(
                activityLogPath: activityLogPath,
                projectPath: projectPath,
                config: config
            )
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func readsCustomMetadataFromEnvironment() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let activityLogPath = temporaryDirectory.appending(component: "test-uuid.xcactivitylog")
        try await fileSystem.writeText("fake", at: activityLogPath)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables["TUIST_BUILD_TAGS"] = "nightly, release-candidate"
        mockedEnvironment.variables["TUIST_BUILD_VALUE_TICKET"] = "PROJ-1234"

        let config = Tuist.test(fullHandle: "tuist/tuist")

        try await subject.uploadBuildRun(
            activityLogPath: activityLogPath,
            projectPath: projectPath,
            config: config,
            scheme: "App",
            configuration: "Debug"
        )

        verify(createBuildService)
            .createBuild(
                fullHandle: .any, serverURL: .any, id: .any, category: .any,
                configuration: .any,
                customMetadata: .matching { metadata in
                    guard let metadata else { return false }
                    let tags = metadata.tags ?? []
                    let values = metadata.values?.additionalProperties ?? [:]
                    return tags.sorted() == ["nightly", "release-candidate"] &&
                        values == ["ticket": "PROJ-1234"]
                },
                duration: .any, files: .any, gitBranch: .any, gitCommitSHA: .any,
                gitRef: .any, gitRemoteURLOrigin: .any, isCI: .any, issues: .any,
                modelIdentifier: .any, macOSVersion: .any, scheme: .any,
                targets: .any, xcodeCacheUploadEnabled: .any, xcodeVersion: .any,
                status: .any, ciRunId: .any, ciProjectHandle: .any,
                ciHost: .any, ciProvider: .any, cacheableTasks: .any,
                casOutputs: .any, machineMetrics: .any
            )
            .called(1)
    }
}
