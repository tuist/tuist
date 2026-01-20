import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct AccountTokensRevokeCommandServiceTests {
    private let subject: AccountTokensRevokeCommandService
    private let revokeAccountTokenService = MockRevokeAccountTokenServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let serverURL: URL

    init() {
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))
        given(serverEnvironmentService)
            .url(configServerURL: .value(serverURL))
            .willReturn(serverURL)
        subject = AccountTokensRevokeCommandService(
            revokeAccountTokenService: revokeAccountTokenService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .withMockedNoora) func revoke_account_token() async throws {
        // Given
        given(revokeAccountTokenService)
            .revokeAccountToken(
                accountHandle: .value("tuist-org"),
                tokenName: .value("ci-token"),
                serverURL: .any
            )
            .willReturn()

        // When
        try await subject.run(
            accountHandle: "tuist-org",
            tokenName: "ci-token",
            path: nil
        )

        // Then
        #expect(ui().contains("The account token 'ci-token' was successfully revoked.") == true)
        verify(revokeAccountTokenService)
            .revokeAccountToken(
                accountHandle: .value("tuist-org"),
                tokenName: .value("ci-token"),
                serverURL: .any
            )
            .called(1)
    }
}
