import FileSystem
import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistLoader
import TuistProcess
import TuistServer
import TuistSupport
import TuistTesting
import TuistXCActivityLog
import TuistXcodeProjectOrWorkspacePathLocator
import XcodeGraph

@testable import TuistInspectCommand
@testable import TuistKit

struct InspectBuildCommandServiceTests {
    private let subject: InspectBuildCommandService
    private let environment: MockEnvironment
    private let configLoader = MockConfigLoading()
    private let xcActivityLogController = MockXCActivityLogControlling()
    private let derivedDataLocator = MockDerivedDataLocating()
    private let fileSystem = FileSystem()
    private let backgroundProcessRunner = MockBackgroundProcessRunning()
    private let dateService = MockDateServicing()
    private let uploadBuildRunService = MockUploadBuildRunServicing()
    private let xcodeProjectOrWorkspacePathLocator = MockXcodeProjectOrWorkspacePathLocating()

    init() throws {
        environment = try #require(Environment.mocked)
        subject = InspectBuildCommandService(
            derivedDataLocator: derivedDataLocator,
            fileSystem: fileSystem,
            configLoader: configLoader,
            xcActivityLogController: xcActivityLogController,
            backgroundProcessRunner: backgroundProcessRunner,
            dateService: dateService,
            uploadBuildRunService: uploadBuildRunService,
            xcodeProjectOrWorkspacePathLocator: xcodeProjectOrWorkspacePathLocator
        )
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: "tuist/tuist"))

        given(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any)
            .willReturn()

        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.schemeName = "App"
        mockedEnvironment.variables = ["TUIST_INSPECT_BUILD_WAIT": "YES"]

        given(dateService)
            .now()
            .willReturn(
                Date(timeIntervalSinceReferenceDate: 20)
            )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func createsBuild() async throws {
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
        let activityLogUUID = UUID().uuidString
        let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
        let activityLogPath = buildLogsPath.appending(
            component: "\(activityLogUUID).xcactivitylog"
        )
        try await fileSystem.makeDirectory(at: buildLogsPath)
        try await fileSystem.writeText("fake", at: activityLogPath)

        given(xcActivityLogController).mostRecentActivityLogFile(
            projectDerivedDataDirectory: .value(derivedDataPath),
            filter: .any
        ).willReturn(
            .test(
                path: activityLogPath,
                timeStoppedRecording: Date(timeIntervalSinceReferenceDate: 20)
            )
        )

        // When
        try await subject.run(path: nil)

        // Then
        verify(uploadBuildRunService)
            .uploadBuildRun(
                activityLogPath: .value(activityLogPath),
                projectPath: .value(projectPath),
                config: .any
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
        try await fileSystem.makeDirectory(at: buildLogsPath)
        try await fileSystem.writeText("fake", at: activityLogPath)

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

        // When
        try await subject.run(path: nil)

        // Then
        verify(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any)
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
        try await fileSystem.writeText("fake", at: activityLogPath)
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
                components: "\(UUID().uuidString).xcactivitylog"
            )

            try await fileSystem.makeDirectory(at: buildLogsPath)
            try await fileSystem.writeText("fake", at: activityLogPath)
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
        try await fileSystem.writeText("fake", at: activityLogPath)
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
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        uploadBuildRunService.reset()
        given(uploadBuildRunService)
            .uploadBuildRun(activityLogPath: .any, projectPath: .any, config: .any)
            .willProduce { _, _, _ in
                throw UploadBuildRunServiceError.missingFullHandle
            }

        // When / Then
        await #expect(
            throws: UploadBuildRunServiceError.missingFullHandle
        ) {
            try await subject.run(path: projectPath.parentDirectory.pathString)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func uses_activityLog_uuid_as_buildId() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "App.xcodeproj")
        let mockedEnvironment = try #require(Environment.mocked)
        mockedEnvironment.workspacePath = projectPath
        mockedEnvironment.variables["TUIST_INSPECT_BUILD_WAIT"] = "YES"

        given(xcodeProjectOrWorkspacePathLocator)
            .locate(from: .any)
            .willReturn(projectPath)

        let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
        given(derivedDataLocator)
            .locate(for: .any)
            .willReturn(derivedDataPath)
        let activityLogUUID = "5D058318-CD9C-46C5-8D15-7A0330AF73F2"
        let buildLogsPath = derivedDataPath.appending(components: "Logs", "Build")
        let activityLogPath = buildLogsPath.appending(
            component: "\(activityLogUUID).xcactivitylog"
        )
        try await fileSystem.makeDirectory(at: buildLogsPath)
        try await fileSystem.writeText("fake", at: activityLogPath)

        given(xcActivityLogController).mostRecentActivityLogFile(
            projectDerivedDataDirectory: .value(derivedDataPath),
            filter: .any
        ).willReturn(
            .test(
                path: activityLogPath,
                timeStoppedRecording: Date(timeIntervalSinceReferenceDate: 20)
            )
        )

        try await subject.run(path: nil)

        verify(uploadBuildRunService)
            .uploadBuildRun(
                activityLogPath: .value(activityLogPath),
                projectPath: .value(projectPath),
                config: .any
            )
            .called(1)
    }
}
