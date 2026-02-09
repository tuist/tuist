import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistNooraTesting
import TuistServer

@testable import TuistProjectCommand

struct ProjectTokensCreateServiceTests {
    private let createProjectTokenService = MockCreateProjectTokenServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let subject: ProjectTokensCreateService

    init() {
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverEnvironmentService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = ProjectTokensCreateService(
            createProjectTokenService: createProjectTokenService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func create_project_token() async throws {
        // Given
        given(createProjectTokenService)
            .createProjectToken(
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .any
            )
            .willReturn("new-token")

        // When
        try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)

        // Then
        #expect(ui().contains("new-token"))
    }
}
