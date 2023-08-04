import Foundation
import TuistCloud
import TuistCloudTesting
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class CloudOrganizationListServiceTests: TuistUnitTestCase {
    private var listOrganizationsService: MockListOrganizationsService!
    private var subject: CloudOrganizationListService!

    override func setUp() {
        super.setUp()

        listOrganizationsService = .init()
        subject = CloudOrganizationListService(
            listOrganizationsService: listOrganizationsService
        )
    }

    override func tearDown() {
        listOrganizationsService = nil
        subject = nil

        super.tearDown()
    }

    func test_organization_list() async throws {
        // Given
        listOrganizationsService.listOrganizationsStub = { _ in
            [
                CloudOrganization(id: 0, name: "test-one"),
                CloudOrganization(id: 1, name: "test-two"),
            ]
        }

        // When
        try await subject.run(json: false, serverURL: nil)

        // Then
        XCTAssertPrinterOutputContains("""
        Listing all your organizations:
          • test-one
          • test-two
        """)
    }

    func test_organization_list_when_none() async throws {
        // Given
        listOrganizationsService.listOrganizationsStub = { _ in
            []
        }

        // When
        try await subject.run(json: false, serverURL: nil)

        // Then
        XCTAssertPrinterOutputContains(
            "You currently have no Cloud organizations. Create one by running `tuist cloud organization create`."
        )
    }
}
