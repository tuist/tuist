import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistConstants
import TuistOpener
import TuistServer

@testable import TuistProjectCommand

struct ProjectUpdateServiceTests {
    private let opener = MockOpening()
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let updateProjectService = MockUpdateProjectServicing()
    private let subject: ProjectUpdateService

    init() {
        subject = ProjectUpdateService(
            opener: opener,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            updateProjectService: updateProjectService
        )

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(updateProjectService)
            .updateProject(
                fullHandle: .any,
                serverURL: .any,
                defaultBranch: .any,
                visibility: .any
            )
            .willReturn(.test())
    }

    @Test(.withMockedNoora) func run_when_full_handle_is_not_provided() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    fullHandle: "tuist/tuist"
                )
            )

        // When
        try await subject.run(
            fullHandle: nil,
            defaultBranch: "new-default-branch",
            visibility: .public,
            path: nil
        )

        // Then
        verify(updateProjectService)
            .updateProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                defaultBranch: .value("new-default-branch"),
                visibility: .value(.public)
            )
            .called(1)
    }

    @Test func run_when_full_handle_is_not_provided_and_is_not_in_config() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    fullHandle: nil
                )
            )

        // When / Then
        await #expect(throws: ProjectUpdateServiceError.missingFullHandle) {
            try await subject.run(
                fullHandle: nil,
                defaultBranch: "new-default-branch",
                visibility: nil,
                path: nil
            )
        }
    }

    @Test(.withMockedNoora) func run_when_full_handle_is_provided() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        // When
        try await subject.run(
            fullHandle: "tuist/tuist",
            defaultBranch: "new-default-branch",
            visibility: nil,
            path: nil
        )

        // Then
        verify(updateProjectService)
            .updateProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                defaultBranch: .value("new-default-branch"),
                visibility: .value(nil)
            )
            .called(1)
    }
}
