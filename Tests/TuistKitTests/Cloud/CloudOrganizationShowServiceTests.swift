import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class CloudOrganizationShowServiceTests: TuistUnitTestCase {
    private var getOrganizationService: MockGetOrganizationServicing!
    private var getOrganizationUsageService: MockGetOrganizationUsageServicing!
    private var subject: CloudOrganizationShowService!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()
        getOrganizationService = .init()
        getOrganizationUsageService = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))
        subject = CloudOrganizationShowService(
            getOrganizationService: getOrganizationService,
            getOrganizationUsageService: getOrganizationUsageService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        getOrganizationService = nil
        getOrganizationUsageService = nil
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

        given(getOrganizationUsageService)
            .getOrganizationUsage(organizationName: .any, serverURL: .any)
            .willReturn(.test(currentMonthRemoteCacheHits: 210))

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

        \(TerminalStyle.bold.open)Usage\(TerminalStyle.reset.open) (current calendar month)
        Remote cache hits: 210

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
        given(getOrganizationUsageService)
            .getOrganizationUsage(organizationName: .any, serverURL: .any)
            .willReturn(.test())

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
