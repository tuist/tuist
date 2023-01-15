import XCTest
import TuistSupport
import TuistCloudTesting

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

    func test_cloud_init_without_URL() async throws {
        // Given
        var createdProjectName: String?
        var createdProjectOrganization: String?
        var createdProjectURL: URL?
        createProjectService.createProjectStub = {
            createdProjectName = $0
            createdProjectOrganization = $1
            createdProjectURL = $2
        }
        
        // When
        try await subject.createProject(
            name: "tuist",
            owner: "tuist-org",
            url: nil
        )

        // Then
        XCTAssertEqual(createdProjectName, "tuist")
        XCTAssertEqual(createdProjectOrganization, "tuist-org")
        XCTAssertEqual(createdProjectURL, URL(string: Constants.tuistCloudURL))
    }
    
    func test_cloud_init_with_URL() async throws {
        // Given
        var createdProjectURL: URL?
        createProjectService.createProjectStub = {
            createdProjectURL = $2
        }
        
        // When
        try await subject.createProject(
            name: "tuist",
            owner: "tuist-org",
            url: "https://my.url"
        )

        // Then
        XCTAssertEqual(createdProjectURL, URL(string: "https://my.url"))
    }
}
