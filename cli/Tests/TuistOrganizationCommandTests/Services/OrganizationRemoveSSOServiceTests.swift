import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistNooraTesting
import TuistServer

@testable import TuistOrganizationCommand

struct OrganizationRemoveSSOServiceTests {
    private let updateOrganizationService: MockUpdateOrganizationServicing
    private let subject: OrganizationRemoveSSOService
    private let configLoader: MockConfigLoading
    private let serverURL: URL

    init() {
        updateOrganizationService = MockUpdateOrganizationServicing()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))

        subject = OrganizationRemoveSSOService(
            updateOrganizationService: updateOrganizationService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func organization_remove_sso() async throws {
        // Given
        given(updateOrganizationService)
            .updateOrganization(
                organizationName: .value("tuist"),
                serverURL: .value(serverURL),
                ssoOrganization: .value(nil)
            )
            .willReturn(.test())

        // When
        try await subject.run(
            organizationName: "tuist",
            directory: nil
        )

        // Then
        #expect(
            ui().contains(
                """
                SSO for tuist was removed.
                """
            )
        )
    }
}
