import Foundation
import Mockable
import MockableTest
import TuistServer
import TuistGraph
import TuistLoaderTesting
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class CloudOrganizationUpdateSSOServiceTests: TuistUnitTestCase {
    private var updateOrganizationService: MockUpdateOrganizationServicing!
    private var subject: CloudOrganizationUpdateSSOService!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()

        updateOrganizationService = .init()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }

        subject = CloudOrganizationUpdateSSOService(
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
        // Given
        given(updateOrganizationService)
            .updateOrganization(
                organizationName: .value("tuist"),
                serverURL: .value(cloudURL),
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
        XCTAssertPrinterOutputContains("""
        tuist now uses Google SSO with tuist.io. Users authenticated with the tuist.io SSO organization will automatically have access to the tuist projects.
        """)
    }
}
