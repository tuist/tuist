import Foundation
import MockableTest
import XcodeProjectGenerator
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class CloudProjectDeleteServiceTests: TuistUnitTestCase {
    private var getProjectService: MockGetProjectServicing!
    private var deleteProjectService: MockDeleteProjectServicing!
    private var credentialsStore: MockCloudCredentialsStoring!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!
    private var subject: CloudProjectDeleteService!

    override func setUp() {
        super.setUp()

        getProjectService = .init()
        deleteProjectService = .init()
        credentialsStore = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))
        subject = CloudProjectDeleteService(
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
                accountName: .value("tuist"),
                projectName: .value("project"),
                serverURL: .value(cloudURL)
            )
            .willReturn(
                .test(id: 0, fullName: "tuist/tuist")
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
        try await subject.run(projectName: "project", organizationName: "tuist", directory: nil)
    }
}
