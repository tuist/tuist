#if canImport(TuistCloud)
    import Foundation
    import TuistCloud
    import TuistCloudTesting
    import TuistSupportTesting
    import TuistLoaderTesting
    import TuistGraph
    import XCTest
    @testable import TuistKit

    final class CloudOrganizationInviteServiceTests: TuistUnitTestCase {
        private var createOrganizationInviteService: MockCreateOrganizationInviteService!
        private var subject: CloudOrganizationInviteService!
        private var configLoader: MockConfigLoader!
        private var cloudURL: URL!
        
        override func setUp() {
            super.setUp()

            createOrganizationInviteService = .init()
            configLoader = MockConfigLoader()
            cloudURL = URL(string: "https://test.cloud.tuist.io")!
            configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL))}
            subject = CloudOrganizationInviteService(
                createOrganizationInviteService: createOrganizationInviteService,
                configLoader: configLoader
            )
        }

        override func tearDown() {
            createOrganizationInviteService = nil
            configLoader = nil
            cloudURL = nil
            subject = nil
            super.tearDown()
        }

        func test_invite() async throws {
            // Given
            createOrganizationInviteService.createOrganizationInviteStub = { _, _, _ in
                .test(
                    inviteeEmail: "tuist@test.io",
                    token: "invitation-token"
                )
            }

            // When
            try await subject.run(
                organizationName: "tuist",
                email: "tuist@test.io",
                directory: nil
            )

            // Then
            XCTAssertPrinterOutputContains("""
            tuist@test.io was successfully invited to the tuist organization 🎉

            You can also share with them the invite link directly: \(cloudURL.absoluteString)/auth/invitations/invitation-token
            """)
        }
    }
#endif
