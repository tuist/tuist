import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistNooraTesting
import TuistServer

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
                ssoOrganization: .value(.google("tuist.io")),
                ssoAutomaticEnrollment: .value(nil)
            )
            .willReturn(.test())

        // When
        try await subject.run(
            organizationName: "tuist",
            provider: .google,
            organizationId: "tuist.io",
            enrollmentPolicy: nil,
            directory: nil
        )

        // Then
        #expect(
            logOutput().contains(
                """
                tuist now uses Google SSO with tuist.io. No enrollment policy was specified.
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
                ssoOrganization: .value(.okta("tuist.okta.com")),
                ssoAutomaticEnrollment: .value(nil)
            )
            .willReturn(.test())

        // When
        try await subject.run(
            organizationName: "tuist",
            provider: .okta,
            organizationId: "tuist.okta.com",
            enrollmentPolicy: nil,
            directory: nil
        )

        // Then
        #expect(
            logOutput().contains(
                """
                tuist now uses Okta SSO with tuist.okta.com. No enrollment policy was specified.
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_update_sso_with_explicit_automatic_enrollment() async throws {
        given(updateOrganizationService)
            .updateOrganization(
                organizationName: .value("tuist"),
                serverURL: .value(serverURL),
                ssoOrganization: .value(.okta("tuist.okta.com")),
                ssoAutomaticEnrollment: .value(true)
            )
            .willReturn(.test())

        try await subject.run(
            organizationName: "tuist",
            provider: .okta,
            organizationId: "tuist.okta.com",
            enrollmentPolicy: .automatic,
            directory: nil
        )

        #expect(
            logOutput().contains(
                """
                tuist now uses Okta SSO with tuist.okta.com. Authenticated users will automatically have access to the tuist projects.
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_update_sso_with_explicit_invitation_only_enrollment() async throws {
        given(updateOrganizationService)
            .updateOrganization(
                organizationName: .value("tuist"),
                serverURL: .value(serverURL),
                ssoOrganization: .value(.google("tuist.io")),
                ssoAutomaticEnrollment: .value(false)
            )
            .willReturn(.test())

        try await subject.run(
            organizationName: "tuist",
            provider: .google,
            organizationId: "tuist.io",
            enrollmentPolicy: .invitationOnly,
            directory: nil
        )

        #expect(
            logOutput().contains(
                """
                tuist now uses Google SSO with tuist.io. Users need an invitation to access the tuist projects.
                """
            )
        )
    }
}
