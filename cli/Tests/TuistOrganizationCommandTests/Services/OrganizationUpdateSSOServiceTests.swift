import Foundation
import Mockable
import TuistConfigLoader
import TuistServer
import Testing

@testable import TuistOrganizationCommand

struct OrganizationUpdateSSOServiceTests {
    private let updateOrganizationService: MockUpdateOrganizationServicing
    private let subject: OrganizationUpdateSSOService
    private let configLoader: MockConfigLoading
    private let serverURL: URL

    init() {
        updateOrganizationService = MockUpdateOrganizationServicing()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))

        subject = OrganizationUpdateSSOService(
            updateOrganizationService: updateOrganizationService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func organization_update_sso() async throws {
        // Given
        given(updateOrganizationService)
            .updateOrganization(
                organizationName: .value("tuist"),
                serverURL: .value(serverURL),
                ssoOrganization: .value(.google("tuist.io"))
            )
            .willReturn(.test())

        // When
        try await subject.run(
            organizationName: "tuist",
            provider: .google,
            organizationId: "tuist.io",
            directory: nil
        )

        // Then
        #expect(
            ui().contains(
                """
                tuist now uses Google SSO with tuist.io. Users authenticated with the tuist.io SSO organization will automatically have access to the tuist projects.
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_update_sso_with_okta() async throws {
        // Given
        given(updateOrganizationService)
            .updateOrganization(
                organizationName: .value("tuist"),
                serverURL: .value(serverURL),
                ssoOrganization: .value(.okta("tuist.okta.com"))
            )
            .willReturn(.test())

        // When
        try await subject.run(
            organizationName: "tuist",
            provider: .okta,
            organizationId: "tuist.okta.com",
            directory: nil
        )

        // Then
        #expect(
            ui().contains(
                """
                tuist now uses Okta SSO with tuist.okta.com. Users authenticated with the tuist.okta.com SSO organization will automatically have access to the tuist projects.
                """
            )
        )
    }
}
