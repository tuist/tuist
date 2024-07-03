import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class ProjectListServiceTests: TuistUnitTestCase {
    private var listProjectsService: MockListProjectsServicing!
    private var subject: ProjectListService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()
        listProjectsService = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = ProjectListService(
            listProjectsService: listProjectsService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        listProjectsService = nil
        configLoader = nil
        serverURL = nil
        subject = nil

        super.tearDown()
    }

    func test_project_list() async throws {
        // Given
        given(listProjectsService)
            .listProjects(serverURL: .value(serverURL))
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
            .listProjects(serverURL: .value(serverURL))
            .willReturn([])

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        XCTAssertPrinterOutputContains(
            "You currently have no Tuist projects. Create one by running `tuist project create`."
        )
    }
}
