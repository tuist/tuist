import Foundation
import TuistCloud
import TuistCloudTesting
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class CloudProjectListServiceTests: TuistUnitTestCase {
    private var listProjectsService: MockListProjectsService!
    private var subject: CloudProjectListService!

    override func setUp() {
        super.setUp()

        listProjectsService = .init()
        subject = CloudProjectListService(
            listProjectsService: listProjectsService
        )
    }

    override func tearDown() {
        listProjectsService = nil
        subject = nil

        super.tearDown()
    }

    func test_project_list() async throws {
        // Given
        listProjectsService.listProjectsStub = { _, _, _ in
            [
                .test(id: 0, fullName: "tuist/test-one"),
                .test(id: 1, fullName: "tuist/test-two"),
            ]
        }

        // When
        try await subject.run(json: false, serverURL: nil)

        // Then
        XCTAssertPrinterOutputContains("""
        Listing all your projects:
          • tuist/test-one
          • tuist/test-two
        """)
    }

    func test_project_list_when_none() async throws {
        // Given
        listProjectsService.listProjectsStub = { _, _, _ in
            []
        }

        // When
        try await subject.run(json: false, serverURL: nil)

        // Then
        XCTAssertPrinterOutputContains(
            "You currently have no Cloud projects. Create one by running `tuist cloud project create`."
        )
    }
}
