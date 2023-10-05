#if canImport(TuistCloud)
    import Foundation
    import TuistCloud
    import TuistCloudTesting
    import TuistSupportTesting
    import XCTest
    @testable import TuistKit

    final class CloudOrganizationInviteServiceTests: TuistUnitTestCase {
        private var createOrganizationInviteService: MockCreateOrganizationInviteService!
        private var subject: CloudOrganizationInviteService!

        override func setUp() {
            super.setUp()

            createOrganizationInviteService = .init()
            subject = CloudOrganizationInviteService(
                createOrganizationInviteService: createOrganizationInviteService
            )
        }

        override func tearDown() {
            createOrganizationInviteService = nil
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
                serverURL: nil
            )

            // Then
            XCTAssertPrinterOutputContains("""
            tuist@test.io was successfully invited to the tuist organization 🎉

            You can also share with them the invite link directly: https://cloud.tuist.io/auth/invitations/invitation-token
            """)
        }
    }
#endif
