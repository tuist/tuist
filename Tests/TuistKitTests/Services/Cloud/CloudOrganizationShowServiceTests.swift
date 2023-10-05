#if canImport(TuistCloud)
    import Foundation
    import TuistCloud
    import TuistCloudTesting
    import TuistSupport
    import TuistSupportTesting
    import XCTest
    @testable import TuistKit

    final class CloudOrganizationShowServiceTests: TuistUnitTestCase {
        private var getOrganizationService: MockGetOrganizationService!
        private var subject: CloudOrganizationShowService!

        override func setUp() {
            super.setUp()

            getOrganizationService = .init()
            subject = CloudOrganizationShowService(
                getOrganizationService: getOrganizationService
            )
        }

        override func tearDown() {
            getOrganizationService = nil
            subject = nil

            super.tearDown()
        }

        func test_organization_show() async throws {
            // Given
            getOrganizationService.getOrganizationStub = { _, _ in
                .test(
                    name: "test-one",
                    plan: .team,
                    members: [
                        .test(
                            name: "name-one",
                            email: "name-one@email.io",
                            role: .user
                        ),
                        .test(
                            name: "name-two",
                            email: "name-two@email.io",
                            role: .admin
                        ),
                    ],
                    invitations: [
                        .test(
                            inviteeEmail: "invitee@email.io",
                            inviter: .test(name: "some-inviter")
                        ),
                    ]
                )
            }

            // When
            try await subject.run(
                organizationName: "tuist",
                json: false,
                serverURL: nil
            )

            // Then
            XCTAssertPrinterOutputContains("""
            \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
            Name: test-one
            Plan: Team

            \(TerminalStyle.bold.open)Organization members\(TerminalStyle.reset.open) (total number: 2)
            username  email              role
            name-one  name-one@email.io  user
            name-two  name-two@email.io  admin

            \(TerminalStyle.bold.open)Invitations\(TerminalStyle.reset.open) (total number: 1)
            inviter       invitee email
            some-inviter  invitee@email.io
            """)
        }
    }
#endif
