import MockableTest
import TSCBasic
import TuistServer
import TuistGraph
import TuistGraphTesting
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudInitServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var createProjectService: MockCreateProjectServicing!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!
    private var subject: CloudInitService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionControlling()
        createProjectService = .init()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
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
        given(createProjectService)
            .createProject(
                name: .value("tuist"),
                organization: .value("tuist-org"),
                serverURL: .value(URL(string: Constants.URLs.production)!)
            )
            .willReturn(.test(fullName: "tuist/test"))
        configLoader.loadConfigStub = { _ in Config.test(cloud: nil) }
        configLoader.locateConfigStub = { _ in AbsolutePath("/some-path") }

        // When
        try await subject.createProject(
            name: "tuist",
            organization: "tuist-org",
            directory: nil
        )

        // Then
        XCTAssertPrinterOutputContains("""
        Put the following line into your Tuist/Config.swift (see the docs for more: https://docs.tuist.io/manifests/config/):
        cloud: .cloud(projectId: "tuist/test")
        """)
    }

    func test_cloud_init_when_config_does_not_exist() async throws {
        // Given
        var content: String?
        configLoader.locateConfigStub = { _ in nil }
        fileHandler.stubWrite = { stubContent, _, _ in content = stubContent }
        given(createProjectService)
            .createProject(
                name: .value("tuist"),
                organization: .value("tuist-org"),
                serverURL: .value(URL(string: Constants.URLs.production)!)
            )
            .willReturn(.test(fullName: "tuist/test"))

        // When
        try await subject.createProject(
            name: "tuist",
            organization: "tuist-org",
            directory: nil
        )

        // Then
        XCTAssertEqual("""
        import ProjectDescription

        let config = Config(
            cloud: .cloud(projectId: "tuist/test")
        )

        """, content)
        XCTAssertPrinterOutputContains("Tuist Cloud was successfully initialized.")
    }

    func test_cloud_init_when_cloud_exists() async throws {
        // Given
        configLoader.loadConfigStub = { _ in
            Config.test(cloud: Cloud.test(url: self.cloudURL))
        }

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.createProject(
                name: "tuist",
                organization: "tuist-org",
                directory: nil
            ),
            CloudInitServiceError.cloudAlreadySetUp
        )
    }
}
