import Foundation
import Mockable
import MockableTest
import TuistApp
import TuistGraph
import TuistLoaderTesting
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class CloudOrganizationListServiceTests: TuistUnitTestCase {
    private var listOrganizationsService: MockListOrganizationsServicing!
    private var subject: CloudOrganizationListService!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()

        listOrganizationsService = .init()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }

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
