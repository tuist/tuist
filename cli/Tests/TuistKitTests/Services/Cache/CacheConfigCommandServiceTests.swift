import Foundation
import Mockable
import Testing
import TuistCAS
import TuistCore
import TuistEnvironment
import TuistHTTP
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit
@testable import TuistOIDC

struct CacheConfigCommandServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let cacheURL = URL(string: "https://cache.tuist.dev")!
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let serverAuthenticationController = MockServerAuthenticationControlling()
    private let cacheURLStore = MockCacheURLStoring()
    private let fullHandleService = MockFullHandleServicing()
    private let ciOIDCAuthenticator = MockCIOIDCAuthenticating()
    private let exchangeOIDCTokenService = MockExchangeOIDCTokenServicing()
    private let subject: CacheConfigCommandService

    init() {
        given(serverEnvironmentService)
            .url()
            .willReturn(serverURL)

        given(fullHandleService)
            .parse(.any)
            .willReturn((accountHandle: "my-account", projectHandle: "my-project"))

        given(cacheURLStore)
            .getCacheURL(for: .any, accountHandle: .any)
            .willReturn(cacheURL)

        subject = CacheConfigCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            cacheURLStore: cacheURLStore,
            fullHandleService: fullHandleService,
            ciOIDCAuthenticator: ciOIDCAuthenticator,
            exchangeOIDCTokenService: exchangeOIDCTokenService
        )
    }

    @Test(.withMockedEnvironment())
    func run_uses_tuist_token_when_set() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_TOKEN"] = "account-token-123"

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            url: nil
        )

        // Then
        verify(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .called(0)

        verify(ciOIDCAuthenticator)
            .fetchOIDCToken()
            .called(0)
    }

    @Test(.withMockedEnvironment())
    func run_uses_existing_token_when_authenticated() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("existing-token"))

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            url: nil
        )

        // Then
        verify(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .called(1)

        verify(ciOIDCAuthenticator)
            .fetchOIDCToken()
            .called(0)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies())
    func run_authenticates_with_oidc_when_not_authenticated() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(nil)

        given(ciOIDCAuthenticator)
            .fetchOIDCToken()
            .willReturn("oidc-jwt-token")

        given(exchangeOIDCTokenService)
            .exchangeOIDCToken(oidcToken: .value("oidc-jwt-token"), serverURL: .any)
            .willReturn("tuist-access-token")

        let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        accessToken: "tuist-access-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            url: nil
        )

        // Then
        verify(ciOIDCAuthenticator)
            .fetchOIDCToken()
            .called(1)

        verify(exchangeOIDCTokenService)
            .exchangeOIDCToken(oidcToken: .value("oidc-jwt-token"), serverURL: .any)
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func run_throws_when_not_authenticated_and_oidc_not_available() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(nil)

        given(ciOIDCAuthenticator)
            .fetchOIDCToken()
            .willThrow(CIOIDCAuthenticatorError.unsupportedCIEnvironment)

        // When/Then
        await #expect(throws: CacheConfigCommandServiceError.notAuthenticated) {
            try await subject.run(
                fullHandle: "my-account/my-project",
                json: true,
                forceRefresh: false,
                url: nil
            )
        }
    }

    @Test(.withMockedEnvironment())
    func run_uses_custom_server_url_when_provided() async throws {
        // Given
        let customServerURL = "https://custom.tuist.dev"

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            url: customServerURL
        )

        // Then
        verify(serverAuthenticationController)
            .authenticationToken(serverURL: .value(URL(string: customServerURL)!))
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func run_throws_when_server_url_is_invalid() async throws {
        // When/Then
        await #expect(throws: CacheConfigCommandServiceError.invalidServerURL("not a url")) {
            try await subject.run(
                fullHandle: "my-account/my-project",
                json: true,
                forceRefresh: false,
                url: "not a url"
            )
        }
    }

    @Test(.withMockedEnvironment())
    func run_parses_full_handle_correctly() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            url: nil
        )

        // Then
        verify(fullHandleService)
            .parse(.value("my-account/my-project"))
            .called(1)

        verify(cacheURLStore)
            .getCacheURL(for: .any, accountHandle: .value("my-account"))
            .called(1)
    }
}
