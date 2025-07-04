import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistAnalytics
import TuistCore
import TuistServer
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct TuistAnalyticsServerBackendTests {
    private var fullHandle = "tuist-org/tuist"
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var analyticsArtifactUploadService: MockAnalyticsArtifactUploadServicing!
    private var subject: TuistAnalyticsServerBackend!

    init() throws {
        createCommandEventService = .init()
        cacheDirectoriesProvider = .init()
        analyticsArtifactUploadService = .init()
        cacheDirectoriesProvider = .init()
        subject = TuistAnalyticsServerBackend(
            fullHandle: fullHandle,
            url: Constants.URLs.production,
            createCommandEventService: createCommandEventService,
            fileHandler: FileHandler.shared,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            analyticsArtifactUploadService: analyticsArtifactUploadService,
            fileSystem: FileSystem()
        )
    }

    @Test(.inTemporaryDirectory, .withMockedLogger(), .withMockedEnvironment()) func test_send_when_is_not_ci() async throws {
        try await withMockedDependencies {
            // Given
            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.runs))
                .willReturn(try #require(FileSystem.temporaryTestDirectory))
            let event = CommandEvent.test()
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = [:]
            given(createCommandEventService)
                .createCommandEvent(
                    commandEvent: .value(event),
                    projectId: .value(fullHandle),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(
                    .test(
                        id: UUID().uuidString,
                        url: URL(string: "https://tuist.dev/tuist-org/tuist/runs/10")!
                    )
                )

            // When
            let _: ServerCommandEvent = try await subject.send(commandEvent: event)

            // Then
            TuistTest.doesntExpectLogs("You can view a detailed report at: https://tuist.dev/tuist-org/tuist/runs/10")
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func test_send_when_is_ci() async throws {
        try await withMockedDependencies {
            // Given
            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.runs))
                .willReturn(try #require(FileSystem.temporaryTestDirectory))
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = ["CI": "1"]

            let event = CommandEvent.test()
            let serverCommandEvent: ServerCommandEvent = .test()
            given(createCommandEventService)
                .createCommandEvent(
                    commandEvent: .value(event),
                    projectId: .value(fullHandle),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(serverCommandEvent)

            // When
            let got: ServerCommandEvent = try await subject.send(commandEvent: event)

            // Then
            #expect(got == serverCommandEvent)
        }
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment()) func test_send_when_is_ci_and_result_bundle_exists() async throws {
        try await withMockedDependencies {
            // Given
            let fileSystem = FileSystem()
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = ["CI": "1"]
            let event = CommandEvent.test()
            let eventID = UUID().uuidString
            let serverCommandEvent: ServerCommandEvent = .test(id: eventID)
            given(createCommandEventService)
                .createCommandEvent(
                    commandEvent: .value(event),
                    projectId: .value(fullHandle),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(serverCommandEvent)

            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(.runs))
                .willReturn(try #require(FileSystem.temporaryTestDirectory))

            let resultBundle =
                try cacheDirectoriesProvider
                    .cacheDirectory(for: .runs)
                    .appending(components: event.runId, "\(Constants.resultBundleName).xcresult")
            try await fileSystem.makeDirectory(at: resultBundle)

            given(analyticsArtifactUploadService)
                .uploadResultBundle(
                    .value(resultBundle),
                    commandEventId: .value(eventID),
                    serverURL: .value(Constants.URLs.production)
                )
                .willReturn(())

            // When
            let got: ServerCommandEvent = try await subject.send(commandEvent: event)

            // Then
            #expect(got == serverCommandEvent)
            let exists = try await fileSystem.exists(resultBundle)
            #expect(exists == false)
        }
    }
}
