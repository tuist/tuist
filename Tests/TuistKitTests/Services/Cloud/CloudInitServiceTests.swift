import TuistCloudTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudInitServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionController!
    private var createProjectService: MockCreateProjectService!
    private var subject: CloudInitService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        createProjectService = MockCreateProjectService()
        subject = CloudInitService(
            cloudSessionController: cloudSessionController,
            createProjectService: createProjectService
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        createProjectService = nil
        subject = nil
        super.tearDown()
    }

    func test_cloud_init() async throws {
        // Given
        var createdProjectName: String?
        var createdProjectOrganization: String?
        var createdProjectURL: URL?
        createProjectService.createProjectStub = {
            createdProjectName = $0
            createdProjectOrganization = $1
            createdProjectURL = $2

            return "slug"
        }

        // When
        try await subject.createProject(
            name: "tuist",
            owner: "tuist-org",
            url: Constants.tuistCloudURL
        )

        // Then
        XCTAssertEqual(createdProjectName, "tuist")
        XCTAssertEqual(createdProjectOrganization, "tuist-org")
        XCTAssertEqual(createdProjectURL, URL(string: Constants.tuistCloudURL))
        XCTAssertPrinterOutputContains("""
        Put the following line into your Tuist/Config.swift (see the docs for more: https://docs.tuist.io/manifests/config/):
        cloud: .cloud(projectId: "slug", url: "https://cloud.tuist.io/")
        """)
    }
}
