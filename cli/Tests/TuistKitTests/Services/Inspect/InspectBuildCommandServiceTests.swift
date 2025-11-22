import FileSystem
import Foundation
import Mockable
import Testing
import TuistCI
import TuistCore
import TuistGit
import TuistLoader
import TuistProcess
import TuistServer
import TuistSupport
import TuistTesting
import TuistXCActivityLog
import TuistXcodeProjectOrWorkspacePathLocator
import XcodeGraph

@testable import TuistKit

struct InspectBuildCommandServiceTests {
    private let subject: InspectBuildCommandService
    private let environment: MockEnvironment
    private let configLoader = MockConfigLoading()
    private let xcActivityLogController = MockXCActivityLogControlling()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let fileSystem = FileSystem()
    private let createBuildService = MockCreateBuildServicing()
    private let machineEnvironment = MockMachineEnvironmentRetrieving()
    private let xcodeBuildController = MockXcodeBuildControlling()
    private let backgroundProcessRunner = MockBackgroundProcessRunning()
    private let dateService = MockDateServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let gitController: MockGitControlling
    private let ciController = MockCIControlling()
    private let xcodeProjectOrWorkspacePathLocator = MockXcodeProjectOrWorkspacePathLocating()

    init() throws {
        gitController = MockGitControlling()
        environment = try #require(Environment.mocked)
        subject = InspectBuildCommandService(
            derivedDataLocator: derivedDataLocator,
            fileSystem: fileSystem,
            machineEnvironment: machineEnvironment,
            xcodeBuildController: xcodeBuildController,
            createBuildService: createBuildService,
            configLoader: configLoader,
            xcActivityLogController: xcActivityLogController,
            backgroundProcessRunner: backgroundProcessRunner,
            dateService: dateService,
            serverEnvironmentService: serverEnvironmentService,
            gitController: gitController,
            ciController: ciController,
            xcodeProjectOrWorkspacePathLocator: xcodeProjectOrWorkspacePathLocator
        )
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(createBuildService)
            .createBuild(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                category: .any,
                configuration: .any,
                duration: .any,
                files: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                issues: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                scheme: .any,
                targets: .any,
                xcodeVersion: .any,
                status: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                cacheableTasks: .any,
                casOutputs: .any
            )
            .willReturn(.test())

        given(machineEnvironment)
            .modelIdentifier()
            .willReturn("Mac15,3")

        given(machineEnvironment)
            .macOSVersion
            .willReturn("13.2.0")

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.schemeName = "App"
        mockedEnvironment.variables = ["TUIST_INSPECT_BUILD_WAIT": "YES"]

        given(xcodeBuildController)
            .version()
            .willReturn(Version(16, 0, 0))

        given(dateService)
            .now()
            .willReturn(
                Date(timeIntervalSinceReferenceDate: 20)
            )

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        given(ciController)
            .ciInfo()
            .willReturn(.test())

        Matcher.register([XCActivityIssue].self)
        Matcher.register([XCActivityBuildFile].self)
        Matcher.register([XCActivityTarget].self)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func createsBuild() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.workspacePath = projectPath
        mockedEnvironment.variables["CONFIGURATION"] = "Debug"

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .any)
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(derivedDataPath)
        let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
        let activityLogPath = buildLogsPath.appending(
            components: "\(UUID().uuidString).xcactivitylog"
        )

        given(xcActivityLogController)
            .parse(.value(activityLogPath))
            .willReturn(
                .test(
                    buildStep: .test(
                        errorCount: 1
                    ),
                    category: .incremental,
                    issues: [
                        .test(),
                    ],
                    files: [
                        .test(),
                    ],
                    targets: [
                        .test(),
                    ]
                )
            )
        given(xcActivityLogController).mostRecentActivityLogFile(
            projectDerivedDataDirectory: .value(derivedDataPath),
            filter: .any
        ).willReturn(
            .test(
                path: activityLogPath,
                timeStoppedRecording: Date(timeIntervalSinceReferenceDate: 20)
            )
        )

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

        // When
        try await subject.run(path: nil)

        // Then
        verify(createBuildService)
            .createBuild(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                id: .any,
                category: .value(.incremental),
                configuration: .value("Debug"),
                duration: .value(10000),
                files: .value([.test()]),
                gitBranch: .value("branch"),
                gitCommitSHA: .value("sha"),
                gitRef: .value("git-ref"),
                gitRemoteURLOrigin: .value("https://github.com/tuist/tuist"),
                isCI: .value(false),
                issues: .value([.test()]),
                modelIdentifier: .value("Mac15,3"),
                macOSVersion: .value("13.2.0"),
                scheme: .value("App"),
                targets: .value([.test()]),
                xcodeVersion: .value("16.0.0"),
                status: .value(.failure),
                ciRunId: .value("123"),
                ciProjectHandle: .value("test-project"),
                ciHost: .value("github.com"),
                ciProvider: .value(.github),
                cacheableTasks: .value([]),
                casOutputs: .value([])
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func createsBuild_generated_after_initial_run() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.workspacePath = projectPath

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .any)
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(derivedDataPath)
        let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
        let activityLogPath = buildLogsPath.appending(
            components: "\(UUID().uuidString).xcactivitylog"
        )

        given(xcActivityLogController)
            .parse(.value(activityLogPath))
            .willReturn(
                .test()
            )
        var numberOfAttempts = 0
        given(xcActivityLogController).mostRecentActivityLogFile(
            projectDerivedDataDirectory: .value(derivedDataPath),
            filter: .any
        ).willProduce { _, _ in
            numberOfAttempts = numberOfAttempts + 1
            if numberOfAttempts > 2 {
                return .test(path: activityLogPath, timeStoppedRecording: Date(timeIntervalSinceReferenceDate: 20))
            } else {
                return nil
            }
        }

        gitController.reset()
        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test(ref: nil, branch: "branch", sha: "sha"))

        ciController.reset()
        given(ciController)
            .ciInfo()
            .willReturn(nil)

        // When
        try await subject.run(path: nil)

        // Then
        verify(createBuildService)
            .createBuild(
                fullHandle: .any,
                serverURL: .any,
                id: .any,
                category: .any,
                configuration: .any,
                duration: .any,
                files: .any,
                gitBranch: .any,
                gitCommitSHA: .any,
                gitRef: .any,
                gitRemoteURLOrigin: .any,
                isCI: .any,
                issues: .any,
                modelIdentifier: .any,
                macOSVersion: .any,
                scheme: .any,
                targets: .any,
                xcodeVersion: .any,
                status: .any,
                ciRunId: .any,
                ciProjectHandle: .any,
                ciHost: .any,
                ciProvider: .any,
                cacheableTasks: .any,
                casOutputs: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func when_should_not_wait() async throws {
        // Given
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.variables = [:]
        mockedEnvironment.workspacePath = "/tmp/path"

        given(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(
                .any,
                environment: .matching {
                    $0["TUIST_INSPECT_BUILD_WAIT"] == "YES"
                }
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func createsBuild_with_path_from_cli() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
        try await fileSystem.makeDirectory(at: projectPath)
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.workspacePath = nil

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .value(temporaryDirectory))
            .willReturn(projectPath)
        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(derivedDataPath)
        let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
        let activityLogPath = buildLogsPath.appending(
            components: "\(UUID().uuidString).xcactivitylog"
        )

        try await fileSystem.makeDirectory(at: buildLogsPath)
        try await fileSystem.writeAsPlist(
            XCLogStoreManifestPlist(
                logs: [
                    "id": XCLogStoreManifestPlist.ActivityLog(
                        fileName: "id.xcactivitylog",
                        timeStartedRecording: 10,
                        timeStoppedRecording: 20,
                        signature: "Build Tuist"
                    ),
                ]
            ),
            at: buildLogsPath.appending(component: "LogStoreManifest.plist")
        )
        given(xcActivityLogController).mostRecentActivityLogFile(
            projectDerivedDataDirectory: .value(derivedDataPath),
            filter: .any
        ).willReturn(.test(path: activityLogPath))
        given(xcActivityLogController)
            .parse(.value(activityLogPath))
            .willReturn(.test())

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        // When / Then
        try await subject.run(path: temporaryDirectory.pathString)
    }

    @Test(.withMockedEnvironment())
    func createsBuild_with_path_from_cli_for_xcworkspace() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "InspectBuildCommandServiceTests") {
            temporaryDirectory in
            // Given
            let workspacePath = temporaryDirectory.appending(component: "App.xcworkspace")
            try await fileSystem.makeDirectory(at: workspacePath)
            let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
            try await fileSystem.makeDirectory(at: projectPath)
            let mockedEnvironment = try #require(Environment.mocked)
            mockedEnvironment.workspacePath = nil

            given(xcodeProjectOrWorkspacePathLocator)
                .locate(from: .value(temporaryDirectory))
                .willReturn(workspacePath)

            let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
            given(derivedDataLocator)
                .locate(for: .any)
                .willReturn(derivedDataPath)
            let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
            let activityLogPath = buildLogsPath.appending(
                components: "\(UUID().uuidString).xcacvitiylog"
            )

            try await fileSystem.makeDirectory(at: buildLogsPath)
            try await fileSystem.writeAsPlist(
                XCLogStoreManifestPlist(
                    logs: [
                        "id": XCLogStoreManifestPlist.ActivityLog(
                            fileName: "id.xcactivitylog",
                            timeStartedRecording: 10,
                            timeStoppedRecording: 20,
                            signature: "Build Tuist"
                        ),
                    ]
                ),
                at: buildLogsPath.appending(component: "LogStoreManifest.plist")
            )
            given(xcActivityLogController)
                .parse(.value(activityLogPath))
                .willReturn(.test())
            given(xcActivityLogController).mostRecentActivityLogFile(
                projectDerivedDataDirectory: .value(derivedDataPath),
                filter: .any
            ).willReturn(.test(path: activityLogPath))

            given(gitController)
                .gitInfo(workingDirectory: .any)
                .willReturn(.test())

            // When
            try await subject.run(path: temporaryDirectory.pathString)

            // Then
            verify(derivedDataLocator)
                .locate(for: .value(workspacePath))
                .called(1)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func when_no_logs_exist() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.workspacePath = projectPath

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .any)
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(derivedDataPath)
        given(xcActivityLogController).mostRecentActivityLogFile(
            projectDerivedDataDirectory: .value(derivedDataPath),
            filter: .any
        ).willReturn(nil)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        // When / Then
        await #expect(
            throws: InspectBuildCommandServiceError.mostRecentActivityLogNotFound(projectPath)
        ) {
            try await subject.run(path: nil)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func when_full_handle_not_specified() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
        try await fileSystem.makeDirectory(at: projectPath)
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.workspacePath = nil

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .value(projectPath.parentDirectory))
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(derivedDataPath)
        let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
        let activityLogPath = buildLogsPath.appending(
            components: "\(UUID().uuidString).xcactivitylog"
        )
        try await fileSystem.makeDirectory(at: buildLogsPath)
        try await fileSystem.writeAsPlist(
            XCLogStoreManifestPlist(
                logs: [
                    "id": XCLogStoreManifestPlist.ActivityLog(
                        fileName: "id.xcactivitylog",
                        timeStartedRecording: 10,
                        timeStoppedRecording: 20,
                        signature: "Build Tuist"
                    ),
                ]
            ),
            at: buildLogsPath.appending(component: "LogStoreManifest.plist")
        )
        given(xcActivityLogController)
            .parse(.value(activityLogPath))
            .willReturn(.test())
        given(xcActivityLogController).mostRecentActivityLogFile(
            projectDerivedDataDirectory: .value(derivedDataPath),
            filter: .any
        ).willReturn(.test(path: activityLogPath))
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        // When / Then
        await #expect(
            throws: InspectBuildCommandServiceError.missingFullHandle
        ) {
            try await subject.run(path: projectPath.parentDirectory.pathString)
        }
    }
}
