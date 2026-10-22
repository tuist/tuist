import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistLogging
import TuistNooraTesting
import TuistServer

@testable import TuistOrganizationCommand

struct OrganizationShowServiceTests {
    private let getOrganizationService: MockGetOrganizationServicing
    private let subject: OrganizationShowService
    private let configLoader: MockConfigLoading
    private let serverURL: URL

    init() {
        getOrganizationService = MockGetOrganizationServicing()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = OrganizationShowService(
            getOrganizationService: getOrganizationService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func organization_show() async throws {
        // Given
        given(getOrganizationService)
            .getOrganization(organizationName: .any, serverURL: .any)
            .willReturn(
                .test(
                    name: "test-one",
                    plan: .air,
                    members: [
                        .test(
                            name: "name-one",
                            email: "name-one@email.io",
                            role: .user
                        ),
                        .test(
                            name: "name-two",
                            email: "name-two@email.io",
                            role: .admin
                        ),
                    ],
                    invitations: [
                        .test(
                            inviteeEmail: "invitee@email.io",
                            inviter: .test(name: "some-inviter")
                        ),
                    ]
                )
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            json: false,
            directory: nil
        )

        // Then
        #expect(
            logOutput().contains(
                """
                \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
                Name: test-one
                Plan: Air

                \(TerminalStyle.bold.open)Organization members\(TerminalStyle.reset.open) (total number: 2)
                username  email              role
                name-one  name-one@email.io  user
                name-two  name-two@email.io  admin

                \(TerminalStyle.bold.open)Invitations\(TerminalStyle.reset.open) (total number: 1)
                inviter       invitee email
                some-inviter  invitee@email.io
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_show_when_has_google_as_sso_provider() async throws {
        // Given
        given(getOrganizationService)
            .getOrganization(organizationName: .any, serverURL: .any)
            .willReturn(
                .test(
                    name: "test-one",
                    plan: .pro,
                    ssoOrganization: .google("tuist.io")
                )
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            json: false,
            directory: nil
        )

        // Then
        #expect(
            logOutput().contains(
                """
                \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
                Name: test-one
                Plan: Pro
                SSO: Google (tuist.io)
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_show_when_has_okta_as_sso_provider() async throws {
        // Given
        given(getOrganizationService)
            .getOrganization(organizationName: .any, serverURL: .any)
            .willReturn(
                .test(
                    name: "test-one",
                    plan: .pro,
                    ssoOrganization: .okta("tuist.okta.com")
                )
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            json: false,
            directory: nil
        )

        // Then
        #expect(
            logOutput().contains(
                """
                \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
                Name: test-one
                Plan: Pro
                SSO: Okta (tuist.okta.com)
                """
            )
        )
    }
}
