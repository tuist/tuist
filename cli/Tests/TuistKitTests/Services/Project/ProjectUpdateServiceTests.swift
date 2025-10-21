import Foundation
import Mockable
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

final class ProjectUpdateServiceTests: TuistUnitTestCase {
    private var opener: MockOpening!
    private var configLoader: MockConfigLoading!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var updateProjectService: MockUpdateProjectServicing!
    private var subject: ProjectUpdateService!

    override func setUp() async throws {
        try await super.setUp()

        opener = MockOpening()
        configLoader = MockConfigLoading()
        serverEnvironmentService = MockServerEnvironmentServicing()
        updateProjectService = MockUpdateProjectServicing()
        subject = ProjectUpdateService(
            opener: opener,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            updateProjectService: updateProjectService
        )

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)

        given(updateProjectService)
            .updateProject(
                fullHandle: .any,
                serverURL: .any,
                defaultBranch: .any,
                visibility: .any
            )
            .willReturn(.test())
    }

    override func tearDown() {
        opener = nil
        configLoader = nil
        serverEnvironmentService = nil
        updateProjectService = nil
        subject = nil
        super.tearDown()
    }

    func test_run_when_full_handle_is_not_provided() async throws {
        try await withMockedDependencies {
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(
                    .test(
                        fullHandle: "tuist/tuist"
                    )
                )

            // When
            try await subject.run(
                fullHandle: nil,
                defaultBranch: "new-default-branch",
                visibility: .public,
                path: nil
            )

            // Then
            verify(updateProjectService)
                .updateProject(
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .any,
                    defaultBranch: .value("new-default-branch"),
                    visibility: .value(.public)
                )
                .called(1)
        }
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

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.run(
                fullHandle: nil,
                defaultBranch: "new-default-branch",
                visibility: nil,
                path: nil
            ),
            ProjectUpdateServiceError.missingFullHandle
        )
    }

    func test_run_when_full_handle_is_provided() async throws {
        try await withMockedDependencies {
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())

            // When
            try await subject.run(
                fullHandle: "tuist/tuist",
                defaultBranch: "new-default-branch",
                visibility: nil,
                path: nil
            )

            // Then
            verify(updateProjectService)
                .updateProject(
                    fullHandle: .value("tuist/tuist"),
                    serverURL: .any,
                    defaultBranch: .value("new-default-branch"),
                    visibility: .value(nil)
                )
                .called(1)
        }
    }
}
