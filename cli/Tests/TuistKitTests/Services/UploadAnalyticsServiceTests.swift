import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistHTTP
import TuistServer
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct UploadAnalyticsServiceTests {
    private let fullHandle = "tuist-org/tuist"
    private let serverURL = URL(string: "https://tuist.dev")!
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var analyticsArtifactUploadService: MockAnalyticsArtifactUploadServicing!
    private var fullHandleService: MockFullHandleServicing!
    private var subject: UploadAnalyticsService!

    init() {
        createCommandEventService = .init()
        cacheDirectoriesProvider = .init()
        analyticsArtifactUploadService = .init()
        fullHandleService = .init()
        subject = UploadAnalyticsService(
            createCommandEventService: createCommandEventService,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            analyticsArtifactUploadService: analyticsArtifactUploadService,
            fullHandleService: fullHandleService,
            fileSystem: FileSystem()
        )
    }

    @Test(.inTemporaryDirectory) func upload_creates_command_event() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory)

        let event = CommandEvent.test()
        let serverCommandEvent: ServerCommandEvent = .test(
            id: UUID().uuidString,
            url: URL(string: "https://tuist.dev/tuist-org/tuist/runs/10")!
        )

        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(serverURL)
            )
            .willReturn(serverCommandEvent)

        given(fullHandleService)
            .parse(.value(fullHandle))
            .willReturn(("tuist-org", "tuist"))

        // When
        let got = try await subject.upload(
            commandEvent: event,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        #expect(got == serverCommandEvent)
    }

    @Test(.inTemporaryDirectory) func upload_uploads_result_bundle_when_exists() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory)

        let event = CommandEvent.test()
        let eventID = UUID().uuidString
        let serverCommandEvent: ServerCommandEvent = .test(id: eventID)

        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(serverURL)
            )
            .willReturn(serverCommandEvent)

        given(fullHandleService)
            .parse(.value(fullHandle))
            .willReturn(("tuist-org", "tuist"))

        let resultBundle = temporaryDirectory
            .appending(components: event.runId, "\(Constants.resultBundleName).xcresult")
        try await fileSystem.makeDirectory(at: resultBundle)

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .value(resultBundle),
                accountHandle: .value("tuist-org"),
                projectHandle: .value("tuist"),
                commandEventId: .value(eventID),
                serverURL: .value(serverURL)
            )
            .willReturn(())

        // When
        let got = try await subject.upload(
            commandEvent: event,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        #expect(got == serverCommandEvent)
        let exists = try await fileSystem.exists(resultBundle)
        #expect(exists == false)
    }

    @Test(.inTemporaryDirectory) func upload_does_not_upload_result_bundle_when_not_exists() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory)

        let event = CommandEvent.test()
        let serverCommandEvent: ServerCommandEvent = .test(id: UUID().uuidString)

        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(serverURL)
            )
            .willReturn(serverCommandEvent)

        given(fullHandleService)
            .parse(.value(fullHandle))
            .willReturn(("tuist-org", "tuist"))

        // When
        let got = try await subject.upload(
            commandEvent: event,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        #expect(got == serverCommandEvent)
        verify(analyticsArtifactUploadService)
            .uploadResultBundle(
                .any,
                accountHandle: .any,
                projectHandle: .any,
                commandEventId: .any,
                serverURL: .any
            )
            .called(0)
    }

    @Test(.inTemporaryDirectory) func upload_uses_custom_result_bundle_path_when_provided() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let customResultBundlePath = temporaryDirectory.appending(component: "custom.xcresult")
        try await fileSystem.makeDirectory(at: customResultBundlePath)

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(temporaryDirectory)

        let event = CommandEvent.test(resultBundlePath: customResultBundlePath)
        let eventID = UUID().uuidString
        let serverCommandEvent: ServerCommandEvent = .test(id: eventID)

        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(serverURL)
            )
            .willReturn(serverCommandEvent)

        given(fullHandleService)
            .parse(.value(fullHandle))
            .willReturn(("tuist-org", "tuist"))

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .value(customResultBundlePath),
                accountHandle: .value("tuist-org"),
                projectHandle: .value("tuist"),
                commandEventId: .value(eventID),
                serverURL: .value(serverURL)
            )
            .willReturn(())

        // When
        let got = try await subject.upload(
            commandEvent: event,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        #expect(got == serverCommandEvent)
    }

    @Test(.inTemporaryDirectory) func upload_does_not_delete_result_bundle_outside_runs_directory() async throws {
        // Given
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let runsDirectory = temporaryDirectory.appending(component: "runs")
        try await fileSystem.makeDirectory(at: runsDirectory)

        let customResultBundlePath = temporaryDirectory.appending(component: "custom.xcresult")
        try await fileSystem.makeDirectory(at: customResultBundlePath)

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(runsDirectory)

        let event = CommandEvent.test(resultBundlePath: customResultBundlePath)
        let eventID = UUID().uuidString
        let serverCommandEvent: ServerCommandEvent = .test(id: eventID)

        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(serverURL)
            )
            .willReturn(serverCommandEvent)

        given(fullHandleService)
            .parse(.value(fullHandle))
            .willReturn(("tuist-org", "tuist"))

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .value(customResultBundlePath),
                accountHandle: .value("tuist-org"),
                projectHandle: .value("tuist"),
                commandEventId: .value(eventID),
                serverURL: .value(serverURL)
            )
            .willReturn(())

        // When
        _ = try await subject.upload(
            commandEvent: event,
            fullHandle: fullHandle,
            serverURL: serverURL
        )

        // Then
        let exists = try await fileSystem.exists(customResultBundlePath)
        #expect(exists == true)
    }
}
