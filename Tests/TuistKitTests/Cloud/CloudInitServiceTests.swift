import MockableTest
import Path
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudInitServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var createProjectService: MockCreateProjectServicing!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!
    private var subject: CloudInitService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionControlling()
        createProjectService = .init()
        configLoader = MockConfigLoading()
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
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .value(URL(string: Constants.URLs.production)!)
            )
            .willReturn(.test(fullName: "tuist-org/tuist"))
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Config.test(cloud: nil))
        given(configLoader)
            .locateConfig(at: .any)
            .willReturn(AbsolutePath("/some-path"))

        // When
        try await subject.createProject(
            fullHandle: "tuist-org/tuist",
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
        given(configLoader)
            .locateConfig(at: .any)
            .willReturn(nil)
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)
        fileHandler.stubWrite = { stubContent, _, _ in content = stubContent }
        given(createProjectService)
            .createProject(
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .value(URL(string: Constants.URLs.production)!)
            )
            .willReturn(.test(fullName: "tuist-org/tuist"))

        // When
        try await subject.createProject(
            fullHandle: "tuist-org/tuist",
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
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                Config.test(cloud: Cloud.test(url: cloudURL))
            )

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.createProject(
                fullHandle: "tuist-org/tuist",
                directory: nil
            ),
            CloudInitServiceError.cloudAlreadySetUp
        )
    }
}
