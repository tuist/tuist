#if canImport(TuistCloud)
    import Foundation
    import TuistCloud
    import TuistCloudTesting
    import TuistSupport
    import TuistSupportTesting
    import TuistLoaderTesting
    import TuistGraph
    import XCTest

    @testable import TuistKit

    final class CloudProjectDeleteServiceTests: TuistUnitTestCase {
        private var getProjectService: MockGetProjectService!
        private var deleteProjectService: MockDeleteProjectService!
        private var credentialsStore: MockCredentialsStore!
        private var configLoader: MockConfigLoader!
        private var cloudURL: URL!
        private var subject: CloudProjectDeleteService!

        override func setUp() {
            super.setUp()

            getProjectService = .init()
            deleteProjectService = .init()
            credentialsStore = .init()
            configLoader = MockConfigLoader()
            cloudURL = URL(string: "https://test.cloud.tuist.io")!
            configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL))}
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
            try await subject.run(projectName: "project", organizationName: "tuist", directory: nil)

            // Then
            XCTAssertEqual(0, gotProjectId)
        }
    }
#endif
