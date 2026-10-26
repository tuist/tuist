import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistLogging
import TuistNooraTesting
import TuistServer

@testable import TuistOrganizationCommand

struct OrganizationShowServiceTests {
    private let getOrganizationService: MockGetOrganizationServicing
    private let getOrganizationUsageService: MockGetOrganizationUsageServicing
    private let subject: OrganizationShowService
    private let configLoader: MockConfigLoading
    private let serverURL: URL

    init() {
        getOrganizationService = MockGetOrganizationServicing()
        getOrganizationUsageService = MockGetOrganizationUsageServicing()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = OrganizationShowService(
            getOrganizationService: getOrganizationService,
            getOrganizationUsageService: getOrganizationUsageService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func organization_show() async throws {
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
            .willReturn(
                .test(
                    cacheEgress: .init(
                        used: 120_300_000_000,
                        included: 100_000_000_000,
                        billable: 20_300_000_000,
                        chargeCents: 710
                    ),
                    cacheRequests: .init(used: 412_000, included: 1_000_000, billable: 0, chargeCents: 0),
                    passingTestCases: .init(used: 1_200_000, included: 5_000_000, billable: 0, chargeCents: 0),
                    runnerMinutes: .init(used: 250, included: 100, chargeCents: 1200),
                    estimatedChargeCents: 1910
                )
            )

        // When
        try await subject.run(
            organizationName: "tuist",
            json: false,
            directory: nil
        )

        // Then
        #expect(
            logOutput().contains(
                """
                \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
                Name: test-one
                Plan: Air

                \(TerminalStyle.bold.open)Usage\(TerminalStyle.reset.open) (Oct 22 to Nov 22, 2026)
                Cache egress: 120.3 GB of 100 GB included
                Cache requests: 412,000 of 1,000,000 included
                Passing test cases: 1,200,000 of 5,000,000 included
                Runner minutes: 250 of 100 included
                Estimated charge: $19.10

                \(TerminalStyle.bold.open)Organization members\(TerminalStyle.reset.open) (total number: 2)
                username  email              role
                name-one  name-one@email.io  user
                name-two  name-two@email.io  admin

                \(TerminalStyle.bold.open)Invitations\(TerminalStyle.reset.open) (total number: 1)
                inviter       invitee email
                some-inviter  invitee@email.io
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_show_when_has_google_as_sso_provider() async throws {
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
        #expect(
            logOutput().contains(
                """
                \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
                Name: test-one
                Plan: Pro
                SSO: Google (tuist.io)
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_show_when_has_okta_as_sso_provider() async throws {
        // Given
        given(getOrganizationService)
            .getOrganization(organizationName: .any, serverURL: .any)
            .willReturn(
                .test(
                    name: "test-one",
                    plan: .pro,
                    ssoOrganization: .okta("tuist.okta.com")
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
        #expect(
            logOutput().contains(
                """
                \(TerminalStyle.bold.open)Organization\(TerminalStyle.reset.open)
                Name: test-one
                Plan: Pro
                SSO: Okta (tuist.okta.com)
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_show_with_json_includes_usage() async throws {
        // Given
        given(getOrganizationService)
            .getOrganization(organizationName: .any, serverURL: .any)
            .willReturn(.test(name: "test-one", plan: .pro))
        given(getOrganizationUsageService)
            .getOrganizationUsage(organizationName: .any, serverURL: .any)
            .willReturn(.test(estimatedChargeCents: 1910))

        // When
        try await subject.run(
            organizationName: "tuist",
            json: true,
            directory: nil
        )

        // Then
        let output = logOutput()
        #expect(output.contains("\"usage\""))
        #expect(output.contains("\"estimatedChargeCents\""))
        #expect(output.contains("1910"))
        #expect(output.contains("2026-10-22T08:30:00Z"))
    }
}
