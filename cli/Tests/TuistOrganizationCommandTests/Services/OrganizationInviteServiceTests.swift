import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistNooraTesting
import TuistServer

@testable import TuistOrganizationCommand

struct OrganizationInviteServiceTests {
    private let createOrganizationInviteService: MockCreateOrganizationInviteServicing
    private let subject: OrganizationInviteService
    private let configLoader: MockConfigLoading
    private let serverURL: URL

    init() {
        createOrganizationInviteService = MockCreateOrganizationInviteServicing()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = OrganizationInviteService(
            createOrganizationInviteService: createOrganizationInviteService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func invite() async throws {
        // Given
        given(createOrganizationInviteService)
            .createOrganizationInvite(
                organizationName: .value("tuist"),
                email: .value("tuist@test.io"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                .test(
                    inviteeEmail: "tuist@test.io",
                    token: "invitation-token"
                )
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            email: "tuist@test.io",
            directory: nil
        )

        // Then
        #expect(
            logOutput().contains(
                """
                tuist@test.io was successfully invited to the tuist organization 🎉

                You can also share with them the invite link directly: \(
                    serverURL
                        .absoluteString
                )/auth/invitations/invitation-token
                """
            )
        )
    }
}
