import Foundation
import Mockable
import MockableTest
import TuistServer
import TuistGraph
import TuistLoaderTesting
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class CloudOrganizationRemoveSSOServiceTests: TuistUnitTestCase {
    private var updateOrganizationService: MockUpdateOrganizationServicing!
    private var subject: CloudOrganizationRemoveSSOService!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()

        updateOrganizationService = .init()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }

        subject = CloudOrganizationRemoveSSOService(
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
