import Foundation
import MockableTest
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest
@testable import TuistKit

final class OrganizationShowServiceTests: TuistUnitTestCase {
    private var getOrganizationService: MockGetOrganizationServicing!
    private var getOrganizationUsageService: MockGetOrganizationUsageServicing!
    private var subject: OrganizationShowService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()
        getOrganizationService = .init()
        getOrganizationUsageService = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = OrganizationShowService(
            getOrganizationService: getOrganizationService,
            getOrganizationUsageService: getOrganizationUsageService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        getOrganizationService = nil
        getOrganizationUsageService = nil
        configLoader = nil
        serverURL = nil
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
                    plan: .air,
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
        Plan: Air

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
                    plan: .pro,
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
            Plan: Pro
            SSO: Google (tuist.io)
            """
        )
    }
}
