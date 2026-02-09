import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistServer

@testable import TuistProjectCommand

struct ProjectListServiceTests {
    private let listProjectsService = MockListProjectsServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let subject: ProjectListService

    init() {
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = ProjectListService(
            listProjectsService: listProjectsService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func test_project_list() async throws {
        // Given
        given(listProjectsService)
            .listProjects(serverURL: .value(serverURL))
            .willReturn(
                [
                    .test(id: 0, fullName: "tuist/test-one"),
                    .test(id: 1, fullName: "tuist/test-two"),
                ]
            )

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        #expect(
            ui().contains(
                """
                Listing all your projects:
                  \u{2022} tuist/test-one
                  \u{2022} tuist/test-two
                """
            )
        )
    }

    @Test(.withMockedNoora) func test_project_list_when_none() async throws {
        // Given
        given(listProjectsService)
            .listProjects(serverURL: .value(serverURL))
            .willReturn([])

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        #expect(
            ui().contains(
                "You currently have no Tuist projects. Create one by running `tuist project create`."
            )
        )
    }
}
