#if canImport(TuistCloud)
    import Foundation
    import TuistCloud
    import TuistCloudTesting
    import TuistSupportTesting
    import TuistLoaderTesting
    import TuistGraph
    import XCTest
    @testable import TuistKit

    final class CloudOrganizationListServiceTests: TuistUnitTestCase {
        private var listOrganizationsService: MockListOrganizationsService!
        private var subject: CloudOrganizationListService!
        private var configLoader: MockConfigLoader!
        private var cloudURL: URL!
        
        override func setUp() {
            super.setUp()

            listOrganizationsService = .init()
            configLoader = MockConfigLoader()
            cloudURL = URL(string: "https://test.cloud.tuist.io")!
            configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL))}
            
            subject = CloudOrganizationListService(
                listOrganizationsService: listOrganizationsService,
                configLoader: configLoader
            )
        }

        override func tearDown() {
            listOrganizationsService = nil
            subject = nil

            super.tearDown()
        }

        func test_organization_list() async throws {
            // Given
            listOrganizationsService.listOrganizationsStub = { _ in
                [
                    .test(id: 0, name: "test-one"),
                    .test(id: 1, name: "test-two"),
                ]
            }

            // When
            try await subject.run(json: false, directory: nil)

            // Then
            XCTAssertPrinterOutputContains("""
            Listing all your organizations:
              • test-one
              • test-two
            """)
        }

        func test_organization_list_when_none() async throws {
            // Given
            listOrganizationsService.listOrganizationsStub = { _ in
                []
            }

            // When
            try await subject.run(json: false, directory: nil)

            // Then
            XCTAssertPrinterOutputContains(
                "You currently have no Cloud organizations. Create one by running `tuist cloud organization create`."
            )
        }
    }
#endif
