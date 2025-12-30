import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct ProjectDeleteServiceTests {
    private let getProjectService = MockGetProjectServicing()
    private let deleteProjectService = MockDeleteProjectServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let subject: ProjectDeleteService

    init() {
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = ProjectDeleteService(
            deleteProjectService: deleteProjectService,
            getProjectService: getProjectService,
            configLoader: configLoader
        )
    }

    @Test func project_delete() async throws {
        // Given
        given(getProjectService)
            .getProject(
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                .test(id: 0, fullName: "tuist-org/tuist")
            )
        given(deleteProjectService)
            .deleteProject(
                projectId: .value(0),
                serverURL: .any
            )
            .willReturn(())

        // When / Then
        try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)
    }
}
