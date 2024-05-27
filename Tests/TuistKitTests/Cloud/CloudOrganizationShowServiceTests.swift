import Foundation
import MockableTest
import TuistGraph
import TuistLoaderTesting
import TuistServer
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistKit

final class CloudOrganizationShowServiceTests: TuistUnitTestCase {
    private var getOrganizationService: MockGetOrganizationServicing!
    private var subject: CloudOrganizationShowService!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()
        getOrganizationService = .init()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }
        subject = CloudOrganizationShowService(
            getOrganizationService: getOrganizationService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        getOrganizationService = nil
        configLoader = nil
        cloudURL = nil
        subject = nil

        super.tearDown()
    }

    func test_organization_show() async throws {
        // Given
        given(getOrganizationService)
            .getOrganization(organizationName: .any, serverURL: .any)
            .willReturn(
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
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            json: false,
            directory: nil
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

    func test_organization_show_when_has_sso_provider() async throws {
        // Given
        given(getOrganizationService)
            .getOrganization(organizationName: .any, serverURL: .any)
            .willReturn(
                .test(
                    name: "test-one",
                    plan: .team,
                    ssoOrganization: .google("tuist.io")
                )
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            json: false,
            directory: nil
        )

        // Then
        XCTAssertPrinterOutputContains(
            """
            \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
            Name: test-one
            Plan: Team
            SSO: Google (tuist.io)
            """
        )
    }
}
