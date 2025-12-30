import Foundation
import Mockable
import TuistLoader
import TuistServer
import TuistTesting
import XCTest

@testable import TuistKit

final class OrganizationUpdateSSOServiceTests: TuistUnitTestCase {
    private var updateOrganizationService: MockUpdateOrganizationServicing!
    private var subject: OrganizationUpdateSSOService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()

        updateOrganizationService = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))

        subject = OrganizationUpdateSSOService(
            updateOrganizationService: updateOrganizationService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        updateOrganizationService = nil
        configLoader = nil
        subject = nil

        super.tearDown()
    }

    func test_organization_update_sso() async throws {
        try await withMockedDependencies {
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
            XCTAssertPrinterOutputContains(
                """
                tuist now uses Google SSO with tuist.io. Users authenticated with the tuist.io SSO organization will automatically have access to the tuist projects.
                """
            )
        }
    }

    func test_organization_update_sso_with_okta() async throws {
        try await withMockedDependencies {
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
            XCTAssertPrinterOutputContains(
                """
                tuist now uses Okta SSO with tuist.okta.com. Users authenticated with the tuist.okta.com SSO organization will automatically have access to the tuist projects.
                """
            )
        }
    }
}
