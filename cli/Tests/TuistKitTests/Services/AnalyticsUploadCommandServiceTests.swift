import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct AnalyticsUploadCommandServiceTests {
    private let fullHandle = "tuist-org/tuist"
    private let serverURL = "https://tuist.dev"
    private let uploadAnalyticsService = MockUploadAnalyticsServicing()
    private let configLoader = MockConfigLoading()
    private let subject: AnalyticsUploadCommandService

    init() {
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        subject = AnalyticsUploadCommandService(
            fileSystem: FileSystem(),
            uploadAnalyticsService: uploadAnalyticsService,
            configLoader: configLoader,
            reportOutbox: Self.reportOutbox()
        )
    }

    @Test(.inTemporaryDirectory) func run_uploads_command_event_from_file() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")

        let event = CommandEvent.test()
        let eventData = try JSONEncoder().encode(event)
        try eventData.write(to: eventFilePath.url, options: .atomic)

        let serverCommandEvent: ServerCommandEvent = .test()
        given(uploadAnalyticsService)
            .upload(
                commandEvent: .matching { $0.name == event.name },
                fullHandle: .value(fullHandle),
                serverURL: .value(URL(string: serverURL)!),
                sessionDirectory: .any
            )
            .willReturn(serverCommandEvent)

        // When
        try await subject.run(
            eventFilePath: eventFilePath.pathString,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        verify(uploadAnalyticsService)
            .upload(
                commandEvent: .any,
                fullHandle: .value(fullHandle),
                serverURL: .value(URL(string: serverURL)!),
                sessionDirectory: .any
            )
            .called(1)
    }

    @Test(.inTemporaryDirectory) func run_deletes_event_file_after_upload() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")

        let event = CommandEvent.test()
        let eventData = try JSONEncoder().encode(event)
        try eventData.write(to: eventFilePath.url, options: .atomic)

        let serverCommandEvent: ServerCommandEvent = .test()
        given(uploadAnalyticsService)
            .upload(
                commandEvent: .any,
                fullHandle: .value(fullHandle),
                serverURL: .value(URL(string: serverURL)!),
                sessionDirectory: .any
            )
            .willReturn(serverCommandEvent)

        // When
        try await subject.run(
            eventFilePath: eventFilePath.pathString,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        let exists = try await fileSystem.exists(eventFilePath)
        #expect(exists == false)
    }

    @Test(.inTemporaryDirectory) func run_deletes_event_file_even_on_failure() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")

        let event = CommandEvent.test()
        let eventData = try JSONEncoder().encode(event)
        try eventData.write(to: eventFilePath.url, options: .atomic)

        given(uploadAnalyticsService)
            .upload(
                commandEvent: .any,
                fullHandle: .value(fullHandle),
                serverURL: .value(URL(string: serverURL)!),
                sessionDirectory: .any
            )
            .willThrow(TestError.uploadFailed)

        // When
        await #expect(throws: TestError.self) {
            try await subject.run(
                eventFilePath: eventFilePath.pathString,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
        }

        // Then
        let exists = try await fileSystem.exists(eventFilePath)
        #expect(exists == false)
    }

    @Test(.inTemporaryDirectory) func run_whenUploadTimesOut_deletesEventFile() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")

        let event = CommandEvent.test()
        let eventData = try JSONEncoder().encode(event)
        try eventData.write(to: eventFilePath.url, options: .atomic)
        let subject = AnalyticsUploadCommandService(
            fileSystem: fileSystem,
            uploadAnalyticsService: DelayedUploadAnalyticsService(delay: .seconds(1)),
            configLoader: configLoader,
            reportOutbox: Self.reportOutbox(),
            bestEffortUploadTimeout: .milliseconds(1)
        )

        // When / Then
        await #expect(throws: AnalyticsUploadCommandServiceError.uploadTimedOut) {
            try await subject.run(
                eventFilePath: eventFilePath.pathString,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
        }
        let exists = try await fileSystem.exists(eventFilePath)
        #expect(exists == false)
    }

    @Test(.inTemporaryDirectory) func run_throws_error_for_invalid_server_url() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")

        let event = CommandEvent.test()
        let eventData = try JSONEncoder().encode(event)
        try eventData.write(to: eventFilePath.url, options: .atomic)

        let invalidServerURL = ""

        // When / Then
        await #expect(throws: AnalyticsUploadCommandServiceError.invalidServerURL(invalidServerURL)) {
            try await subject.run(
                eventFilePath: eventFilePath.pathString,
                fullHandle: fullHandle,
                serverURL: invalidServerURL
            )
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        arguments: [["generate"], ["generate", "--path", "/wrong-project"]],
        [false, true]
    )
    func run_loads_authentication_policy_from_the_resolved_project_path(
        commandArguments: [String],
        optionalAuthentication: Bool
    ) async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "app")
        let eventFilePath = temporaryDirectory.appending(component: "event.json")
        try await FileSystem().writeAsJSON(CommandEvent.test(commandArguments: commandArguments), at: eventFilePath)
        let arguments = [
            eventFilePath.pathString, fullHandle, serverURL, temporaryDirectory.pathString,
            "--project-path", projectPath.pathString,
        ]
        let command = try AnalyticsUploadCommand.parse(arguments)
        let resolvedPath = try await CommandArguments.path(in: arguments, command: command)
        #expect(resolvedPath == projectPath)
        let recorder = AuthenticationConfigRecorder()
        let configLoader = MockConfigLoading()
        given(configLoader)
            .loadConfig(path: .value(projectPath))
            .willReturn(
                .test(project: .generated(.test(generationOptions: .test(optionalAuthentication: optionalAuthentication))))
            )
        let subject = AnalyticsUploadCommandService(
            fileSystem: FileSystem(),
            uploadAnalyticsService: RecordingUploadAnalyticsService(recorder: recorder),
            configLoader: configLoader,
            reportOutbox: Self.reportOutbox()
        )

        try await subject.run(
            eventFilePath: try #require(command.eventFilePath),
            fullHandle: try #require(command.fullHandle),
            serverURL: try #require(command.serverURL),
            sessionDirectory: command.sessionDirectory,
            projectPath: command.projectPath
        )

        #expect(await recorder.values() == [optionalAuthentication])
        verify(configLoader).loadConfig(path: .value(projectPath)).called(1)
    }

    @Test(.withMockedEnvironment())
    func legacy_analytics_upload_invocation_keeps_the_working_directory_default() async throws {
        let arguments = ["/event.json", fullHandle, serverURL, "/session"]
        let command = try AnalyticsUploadCommand.parse(arguments)

        let path = try await CommandArguments.path(in: arguments, command: command)

        #expect(command.projectPath == nil)
        #expect(command.sessionDirectory == "/session")
        #expect(path == (try await Environment.current.currentWorkingDirectory()))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func run_enables_optional_authentication_from_repo_config_when_using_short_path_option() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let projectPath = currentWorkingDirectory.appending(component: "Project")
        let event = CommandEvent.test(commandArguments: ["test", "-p", "Project"])
        let eventData = try JSONEncoder().encode(event)
        try eventData.write(to: eventFilePath.url, options: .atomic)
        let recorder = AuthenticationConfigRecorder()
        let configLoader = MockConfigLoading()
        given(configLoader)
            .loadConfig(path: .value(projectPath))
            .willReturn(
                .test(
                    project: .generated(
                        .test(
                            generationOptions: .test(optionalAuthentication: true)
                        )
                    )
                )
            )
        let subject = AnalyticsUploadCommandService(
            fileSystem: FileSystem(),
            uploadAnalyticsService: RecordingUploadAnalyticsService(recorder: recorder),
            configLoader: configLoader,
            reportOutbox: Self.reportOutbox()
        )

        // When
        try await subject.run(
            eventFilePath: eventFilePath.pathString,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        let values = await recorder.values()
        #expect(values == [true])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment()
    ) func run_falls_back_to_required_authentication_when_config_loading_fails_with_short_path_option()
        async throws
    {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")
        let mockedEnvironment = try #require(Environment.mocked)
        let currentWorkingDirectory = try await mockedEnvironment.currentWorkingDirectory()
        let projectPath = currentWorkingDirectory.appending(component: "Project")
        let event = CommandEvent.test(commandArguments: ["test", "-p", "Project"])
        let eventData = try JSONEncoder().encode(event)
        try eventData.write(to: eventFilePath.url, options: .atomic)
        let recorder = AuthenticationConfigRecorder()
        let configLoader = MockConfigLoading()
        given(configLoader)
            .loadConfig(path: .value(projectPath))
            .willThrow(TestError.configLoadFailed)
        let subject = AnalyticsUploadCommandService(
            fileSystem: FileSystem(),
            uploadAnalyticsService: RecordingUploadAnalyticsService(recorder: recorder),
            configLoader: configLoader,
            reportOutbox: Self.reportOutbox()
        )

        // When
        try await subject.run(
            eventFilePath: eventFilePath.pathString,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        let values = await recorder.values()
        #expect(values == [false])
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func run_flushes_the_report_outbox_after_its_own_upload(uploadFails: Bool) async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let eventFilePath = temporaryDirectory.appending(component: "event.json")
        try JSONEncoder().encode(CommandEvent.test()).write(to: eventFilePath.url, options: .atomic)
        let uploadAnalyticsService = MockUploadAnalyticsServicing()
        if uploadFails {
            given(uploadAnalyticsService)
                .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
                .willThrow(TestError.uploadFailed)
        } else {
            given(uploadAnalyticsService)
                .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
                .willReturn(.test())
        }
        let reportOutbox = Self.reportOutbox()
        let subject = AnalyticsUploadCommandService(
            fileSystem: FileSystem(),
            uploadAnalyticsService: uploadAnalyticsService,
            configLoader: configLoader,
            reportOutbox: reportOutbox
        )

        _ = try? await subject.run(eventFilePath: eventFilePath.pathString, fullHandle: fullHandle, serverURL: serverURL)

        verify(reportOutbox).flush().called(1)
    }

    @Test func flushing_the_report_outbox_needs_no_event() async throws {
        let command = try AnalyticsUploadCommand.parse(["--flush-report-outbox"])

        #expect(command.eventFilePath == nil)
        #expect(command.flushReportOutbox)
        #expect(throws: (any Error).self) { try AnalyticsUploadCommand.parse([]) }
        #expect(throws: (any Error).self) { try AnalyticsUploadCommand.parse(["/event.json"]) }
    }
}

private enum TestError: Error {
    case uploadFailed
    case configLoadFailed
}

extension AnalyticsUploadCommandServiceTests {
    fileprivate static func reportOutbox() -> MockReportOutboxing {
        let reportOutbox = MockReportOutboxing()
        given(reportOutbox).flush().willReturn()
        return reportOutbox
    }
}

private actor AuthenticationConfigRecorder {
    private var recordedValues: [Bool] = []

    func record(_ value: Bool) {
        recordedValues.append(value)
    }

    func values() -> [Bool] {
        recordedValues
    }
}

private struct RecordingUploadAnalyticsService: UploadAnalyticsServicing {
    let recorder: AuthenticationConfigRecorder

    func upload(
        commandEvent _: CommandEvent,
        fullHandle _: String,
        serverURL _: URL,
        sessionDirectory _: AbsolutePath?
    ) async throws -> ServerCommandEvent {
        await recorder.record(ServerAuthenticationConfig.current.optionalAuthentication)
        return .test()
    }
}

private struct DelayedUploadAnalyticsService: UploadAnalyticsServicing {
    let delay: Duration

    func upload(
        commandEvent _: CommandEvent,
        fullHandle _: String,
        serverURL _: URL,
        sessionDirectory _: AbsolutePath?
    ) async throws -> ServerCommandEvent {
        try await Task.sleep(for: delay)
        return .test()
    }
}
