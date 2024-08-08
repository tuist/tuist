import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting

@testable import TuistKit

final class ProjectUpdateServiceTests: TuistUnitTestCase {
    private var opener: MockOpening!
    private var configLoader: MockConfigLoading!
    private var serverURLService: MockServerURLServicing!
    private var updateProjectService: MockUpdateProjectServicing!
    private var subject: ProjectUpdateService!

    override func setUp() async throws {
        try await super.setUp()

        opener = MockOpening()
        configLoader = MockConfigLoading()
        serverURLService = MockServerURLServicing()
        updateProjectService = MockUpdateProjectServicing()
        subject = ProjectUpdateService(
            opener: opener,
            configLoader: configLoader,
            serverURLService: serverURLService,
            updateProjectService: updateProjectService
        )

        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)
    }

    override func tearDown() {
        opener = nil
        configLoader = nil
        serverURLService = nil
        updateProjectService = nil
        subject = nil
        super.tearDown()
    }

    func test_run_when_full_handle_is_not_provided() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    fullHandle: "tuist/tuist"
                )
            )
        given(updateProjectService)
            .updateProject(
                fullHandle: .any,
                serverURL: .any,
                defaultBranch: .any
            )
            .willReturn(.test())

        // When
        try await subject.run(fullHandle: nil, defaultBranch: "new-default-branch", path: nil)

        // Then
        verify(updateProjectService)
            .updateProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                defaultBranch: .value("new-default-branch")
            )
            .called(1)
        XCTAssertStandardOutput(pattern: "The project tuist/tuist was successfully updated 🎉")
    }

    func test_run_when_full_handle_is_not_provided_and_is_not_in_config() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    fullHandle: nil
                )
            )
        given(updateProjectService)
            .updateProject(
                fullHandle: .any,
                serverURL: .any,
                defaultBranch: .any
            )
            .willReturn(.test())

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(fullHandle: nil, defaultBranch: "new-default-branch", path: nil),
            ProjectUpdateServiceError.missingFullHandle
        )
    }

    func test_run_when_full_handle_is_provided() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(updateProjectService)
            .updateProject(
                fullHandle: .any,
                serverURL: .any,
                defaultBranch: .any
            )
            .willReturn(.test())

        // When
        try await subject.run(fullHandle: "tuist/tuist", defaultBranch: "new-default-branch", path: nil)

        // Then
        verify(updateProjectService)
            .updateProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any,
                defaultBranch: .value("new-default-branch")
            )
            .called(1)
        XCTAssertStandardOutput(pattern: "The project tuist/tuist was successfully updated 🎉")
    }
}
