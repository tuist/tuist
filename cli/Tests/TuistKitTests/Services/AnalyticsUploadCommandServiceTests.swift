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
            configLoader: configLoader
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
            configLoader: configLoader
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
            configLoader: configLoader
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
}

private enum TestError: Error {
    case uploadFailed
    case configLoadFailed
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
