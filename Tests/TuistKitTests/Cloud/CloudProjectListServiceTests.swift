import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class CloudProjectListServiceTests: TuistUnitTestCase {
    private var listProjectsService: MockListProjectsServicing!
    private var subject: CloudProjectListService!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()
        listProjectsService = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))
        subject = CloudProjectListService(
            listProjectsService: listProjectsService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        listProjectsService = nil
        configLoader = nil
        cloudURL = nil
        subject = nil

        super.tearDown()
    }

    func test_project_list() async throws {
        // Given
        given(listProjectsService)
            .listProjects(serverURL: .value(cloudURL))
            .willReturn(
                [
                    .test(id: 0, fullName: "tuist/test-one"),
                    .test(id: 1, fullName: "tuist/test-two"),
                ]
            )

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        XCTAssertPrinterOutputContains("""
        Listing all your projects:
          • tuist/test-one
          • tuist/test-two
        """)
    }

    func test_project_list_when_none() async throws {
        // Given
        given(listProjectsService)
            .listProjects(serverURL: .value(cloudURL))
            .willReturn([])

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        XCTAssertPrinterOutputContains(
            "You currently have no Cloud projects. Create one by running `tuist cloud project create`."
        )
    }
}
