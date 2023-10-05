#if canImport(TuistCloud)
    import Foundation
    import TuistCloud
    import TuistCloudTesting
    import TuistSupport
    import TuistSupportTesting
    import XCTest
    @testable import TuistKit

    final class CloudProjectDeleteServiceTests: TuistUnitTestCase {
        private var getProjectService: MockGetProjectService!
        private var deleteProjectService: MockDeleteProjectService!
        private var credentialsStore: MockCredentialsStore!
        private var subject: CloudProjectDeleteService!

        override func setUp() {
            super.setUp()

            getProjectService = .init()
            deleteProjectService = .init()
            credentialsStore = .init()
            subject = CloudProjectDeleteService(
                deleteProjectService: deleteProjectService,
                getProjectService: getProjectService,
                credentialsStore: credentialsStore
            )
        }

        override func tearDown() {
            deleteProjectService = nil
            getProjectService = nil
            credentialsStore = nil
            subject = nil

            super.tearDown()
        }

        func test_project_delete() async throws {
            // Given
            getProjectService.getProjectStub = { _, _, _ in
                .test(id: 0, fullName: "tuist/tuist")
            }
            var gotProjectId: Int?
            deleteProjectService.deleteProjectStub = { projectId, _ in
                gotProjectId = projectId
            }
            credentialsStore.credentials[
                URL(string: Constants.tuistCloudURL)!
            ] = .init(token: "token", account: "account")

            // When
            try await subject.run(projectName: "project", organizationName: "tuist", serverURL: nil)

            // Then
            XCTAssertEqual(0, gotProjectId)
        }
    }
#endif
