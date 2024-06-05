import Foundation
import Mockable
import MockableTest
import TuistLoader
import TuistServer
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class CloudOrganizationListServiceTests: TuistUnitTestCase {
    private var listOrganizationsService: MockListOrganizationsServicing!
    private var subject: CloudOrganizationListService!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()

        listOrganizationsService = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))

        subject = CloudOrganizationListService(
            listOrganizationsService: listOrganizationsService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        listOrganizationsService = nil
        subject = nil

        super.tearDown()
    }

    func test_organization_list() async throws {
        // Given
        given(listOrganizationsService).listOrganizations(serverURL: .any)
            .willReturn(
                [
                    "test-one",
                    "test-two",
                ]
            )

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        XCTAssertPrinterOutputContains("""
        Listing all your organizations:
          • test-one
          • test-two
        """)
    }

    func test_organization_list_when_none() async throws {
        // Given
        given(listOrganizationsService).listOrganizations(serverURL: .any)
            .willReturn([])

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        XCTAssertPrinterOutputContains(
            "You currently have no Cloud organizations. Create one by running `tuist cloud organization create`."
        )
    }
}
