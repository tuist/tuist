import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistNooraTesting
import TuistServer

@testable import TuistProjectCommand

struct ProjectTokensListServiceTests {
    private let listProjectTokensService = MockListProjectTokensServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let subject: ProjectTokensListService

    init() {
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverEnvironmentService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = ProjectTokensListService(
            listProjectTokensService: listProjectTokensService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func list_project_tokens() async throws {
        // Given
        given(listProjectTokensService)
            .listProjectTokens(
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .any
            )
            .willReturn(
                [
                    .test(
                        id: "project-token-one",
                        insertedAt: Date(timeIntervalSince1970: 0)
                    ),
                    .test(
                        id: "project-token-two",
                        insertedAt: Date(timeIntervalSince1970: 10)
                    ),
                ]
            )

        // When
        try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)

        // Then
        let output = ui()
        #expect(output.contains("project-token-one"))
        #expect(output.contains("project-token-two"))
        #expect(output.contains("1970-01-01 00:00:00 +0000"))
        #expect(output.contains("1970-01-01 00:00:10 +0000"))
    }

    @Test(.withMockedNoora) func list_project_tokens_when_none_present() async throws {
        // Given
        given(listProjectTokensService)
            .listProjectTokens(
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .any
            )
            .willReturn([])

        // When
        try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)

        // Then
        #expect(
            ui().contains(
                "No project tokens found. Create one by running `tuist project tokens create tuist-org/tuist."
            )
        )
    }
}
