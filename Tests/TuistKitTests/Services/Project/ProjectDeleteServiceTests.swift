import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistKit

final class ProjectDeleteServiceTests: TuistUnitTestCase {
    private var getProjectService: MockGetProjectServicing!
    private var deleteProjectService: MockDeleteProjectServicing!
    private var credentialsStore: MockServerCredentialsStoring!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!
    private var subject: ProjectDeleteService!

    override func setUp() {
        super.setUp()

        getProjectService = .init()
        deleteProjectService = .init()
        credentialsStore = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))
        subject = ProjectDeleteService(
            deleteProjectService: deleteProjectService,
            getProjectService: getProjectService,
            credentialsStore: credentialsStore,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        deleteProjectService = nil
        getProjectService = nil
        credentialsStore = nil
        configLoader = nil
        cloudURL = nil
        subject = nil

        super.tearDown()
    }

    func test_project_delete() async throws {
        // Given
        given(getProjectService)
            .getProject(
                fullHandle: .value("tuist-org/tuist"),
                serverURL: .value(cloudURL)
            )
            .willReturn(
                .test(id: 0, fullName: "tuist-org/tuist")
            )
        given(deleteProjectService)
            .deleteProject(
                projectId: .value(0),
                serverURL: .value(cloudURL)
            )
            .willReturn(())

        given(credentialsStore)
            .get(serverURL: .value(cloudURL))
            .willReturn(.init(token: "token"))

        // When / Then
        try await subject.run(fullHandle: "tuist-org/tuist", directory: nil)
    }
}
