import Foundation
import Mockable
import MockableTest
import TuistLoader
import TuistServer
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class OrganizationRemoveSSOServiceTests: TuistUnitTestCase {
    private var updateOrganizationService: MockUpdateOrganizationServicing!
    private var subject: OrganizationRemoveSSOService!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()

        updateOrganizationService = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))

        subject = OrganizationRemoveSSOService(
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

    func test_organization_remove_sso() async throws {
        // Given
        given(updateOrganizationService)
            .updateOrganization(
                organizationName: .value("tuist"),
                serverURL: .value(cloudURL),
                ssoOrganization: .value(nil)
            )
            .willReturn(.test())

        // When
        try await subject.run(
            organizationName: "tuist",
            directory: nil
        )

        // Then
        XCTAssertPrinterOutputContains("""
        SSO for tuist was removed.
        """)
    }
}
