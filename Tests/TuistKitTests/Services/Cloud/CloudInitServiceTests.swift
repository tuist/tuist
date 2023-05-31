import TSCBasic
import TuistCloudTesting
import TuistGraph
import TuistGraphTesting
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudInitServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionController!
    private var createProjectService: MockCreateProjectService!
    private var configLoader: MockConfigLoader!
    private var subject: CloudInitService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        createProjectService = MockCreateProjectService()
        configLoader = MockConfigLoader()

        subject = CloudInitService(
            cloudSessionController: cloudSessionController,
            createProjectService: createProjectService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        createProjectService = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_cloud_init_when_config_exists() async throws {
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
        configLoader.loadConfigStub = { _ in Config.test(cloud: nil) }
        configLoader.locateConfigStub = { _ in AbsolutePath("/some-path") }

        // When
        try await subject.createProject(
            name: "tuist",
            owner: "tuist-org",
            url: Constants.tuistCloudURL,
            path: nil
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

    func test_cloud_init_when_config_does_not_exist() async throws {
        // Given
        var content: String?
        configLoader.locateConfigStub = { _ in nil }
        fileHandler.stubWrite = { stubContent, _, _ in content = stubContent }
        createProjectService.createProjectStub = { _, _, _ in "slug" }

        // When
        try await subject.createProject(
            name: "tuist",
            owner: "tuist-org",
            url: Constants.tuistCloudURL,
            path: nil
        )

        // Then
        XCTAssertEqual("""
        import ProjectDescription

        let config = Config(
            cloud: .cloud(projectId: "slug", url: "https://cloud.tuist.io/")
        )

        """, content)
        XCTAssertPrinterOutputContains("Tuist Cloud was successfully initialized.")
    }

    func test_cloud_init_when_cloud_exists() async throws {
        // Given
        configLoader.loadConfigStub = { _ in
            Config.test(cloud: Cloud.test())
        }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.createProject(
                name: "tuist",
                owner: "tuist-org",
                url: Constants.tuistCloudURL,
                path: nil
            ),
            CloudInitServiceError.cloudAlreadySetUp
        )
    }
}
