import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistNooraTesting
import TuistServer

@testable import TuistProjectCommand

struct ProjectTokensRevokeServiceTests {
    private let revokeProjectTokenService = MockRevokeProjectTokenServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let subject: ProjectTokensRevokeService

    init() {
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverEnvironmentService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = ProjectTokensRevokeService(
            revokeProjectTokenService: revokeProjectTokenService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func revoke_project_token() async throws {
        // Given
        given(revokeProjectTokenService)
            .revokeProjectToken(
                projectTokenId: .value("project-token-id"),
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .any
            )
            .willReturn()

        // When
        try await subject.run(
            projectTokenId: "project-token-id",
            fullHandle: "tuist-org/tuist",
            directory: nil
        )

        // Then
        #expect(
            ui().contains("The project token project-token-id was successfully revoked.")
        )
    }
}
