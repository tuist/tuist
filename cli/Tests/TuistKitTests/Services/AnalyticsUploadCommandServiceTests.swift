import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistServer
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct AnalyticsUploadCommandServiceTests {
    private let fullHandle = "tuist-org/tuist"
    private let serverURL = "https://tuist.dev"
    private let uploadAnalyticsService = MockUploadAnalyticsServicing()
    private let subject: AnalyticsUploadCommandService

    init() {
        subject = AnalyticsUploadCommandService(
            fileSystem: FileSystem(),
            uploadAnalyticsService: uploadAnalyticsService
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
                serverURL: .value(URL(string: serverURL)!)
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
                serverURL: .value(URL(string: serverURL)!)
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
                serverURL: .value(URL(string: serverURL)!)
            )
            .willReturn(serverCommandEvent)

        // When
        try await subject.run(
            eventFilePath: eventFilePath.pathString,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        // File deletion happens in a deferred Task, so we need a small delay to allow it to complete
        try await Task.sleep(nanoseconds: 100_000_000)
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
                serverURL: .value(URL(string: serverURL)!)
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
        // File deletion happens in a deferred Task, so we need a small delay to allow it to complete
        try await Task.sleep(nanoseconds: 100_000_000)
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
}

private enum TestError: Error {
    case uploadFailed
}
