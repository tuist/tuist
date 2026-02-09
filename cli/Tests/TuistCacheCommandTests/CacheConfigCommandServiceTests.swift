import Foundation
import Mockable
import Path
import Testing
import TuistCAS
import TuistConfig
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistHTTP
import TuistOIDC
import TuistServer
import TuistTesting

@testable import TuistCacheCommand
@testable import TuistOIDC

struct CacheConfigCommandServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let cacheURL = URL(string: "https://cache.tuist.dev")!
    private func makeSubject() -> (
        subject: CacheConfigCommandService,
        serverEnvironmentService: MockServerEnvironmentServicing,
        serverAuthenticationController: MockServerAuthenticationControlling,
        cacheURLStore: MockCacheURLStoring,
        fullHandleService: MockFullHandleServicing,
        configLoader: MockConfigLoading,
        ciOIDCAuthenticator: MockCIOIDCAuthenticating,
        exchangeOIDCTokenService: MockExchangeOIDCTokenServicing
    ) {
        let serverEnvironmentService = MockServerEnvironmentServicing()
        let serverAuthenticationController = MockServerAuthenticationControlling()
        let cacheURLStore = MockCacheURLStoring()
        let fullHandleService = MockFullHandleServicing()
        let configLoader = MockConfigLoading()
        let ciOIDCAuthenticator = MockCIOIDCAuthenticating()
        let exchangeOIDCTokenService = MockExchangeOIDCTokenServicing()

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(url: serverURL))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        given(fullHandleService)
            .parse(.any)
            .willReturn((accountHandle: "my-account", projectHandle: "my-project"))

        given(cacheURLStore)
            .getCacheURL(for: .any, accountHandle: .any)
            .willReturn(cacheURL)

        let subject = CacheConfigCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            cacheURLStore: cacheURLStore,
            fullHandleService: fullHandleService,
            configLoader: configLoader,
            ciOIDCAuthenticator: ciOIDCAuthenticator,
            exchangeOIDCTokenService: exchangeOIDCTokenService
        )

        return (
            subject,
            serverEnvironmentService,
            serverAuthenticationController,
            cacheURLStore,
            fullHandleService,
            configLoader,
            ciOIDCAuthenticator,
            exchangeOIDCTokenService
        )
    }

    @Test(.withMockedEnvironment())
    func run_uses_tuist_token_when_set() async throws {
        // Given
        let (
            subject,
            _,
            serverAuthenticationController,
            _,
            _,
            _,
            ciOIDCAuthenticator,
            _
        ) = makeSubject()
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_TOKEN"] = "account-token-123"
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("account-token-123"))

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            directory: nil,
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

    @Test(.withMockedEnvironment())
    func run_uses_existing_token_when_authenticated() async throws {
        // Given
        let (
            subject,
            _,
            serverAuthenticationController,
            _,
            _,
            _,
            ciOIDCAuthenticator,
            _
        ) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("existing-token"))

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            directory: nil,
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
        let (
            subject,
            _,
            serverAuthenticationController,
            _,
            _,
            _,
            ciOIDCAuthenticator,
            exchangeOIDCTokenService
        ) = makeSubject()
        let environment = try #require(Environment.mocked)
        environment.variables["CI"] = "true"
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
            directory: nil,
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
        let (
            subject,
            _,
            serverAuthenticationController,
            _,
            _,
            _,
            ciOIDCAuthenticator,
            _
        ) = makeSubject()
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
                directory: nil,
                url: nil
            )
        }
    }

    @Test(.withMockedEnvironment())
    func run_uses_custom_server_url_when_provided() async throws {
        // Given
        let (
            subject,
            _,
            serverAuthenticationController,
            _,
            _,
            _,
            _,
            _
        ) = makeSubject()
        let customServerURL = "https://custom.tuist.dev"

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            directory: nil,
            url: customServerURL
        )

        // Then
        verify(serverAuthenticationController)
            .authenticationToken(serverURL: .value(URL(string: customServerURL)!))
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func run_throws_when_server_url_is_invalid() async throws {
        let invalidURL = "http://%"
        let (subject, _, _, _, _, _, _, _) = makeSubject()
        // When/Then
        await #expect(throws: CacheConfigCommandServiceError.invalidServerURL(invalidURL)) {
            try await subject.run(
                fullHandle: "my-account/my-project",
                json: true,
                forceRefresh: false,
                directory: nil,
                url: invalidURL
            )
        }
    }

    @Test(.withMockedEnvironment())
    func run_reads_full_handle_from_config_when_not_provided() async throws {
        let (
            subject,
            _,
            serverAuthenticationController,
            _,
            fullHandleService,
            configLoader,
            _,
            _
        ) = makeSubject()
        configLoader.reset()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(fullHandle: "config-account/config-project", url: serverURL))
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        try await subject.run(
            fullHandle: nil,
            json: true,
            forceRefresh: false,
            directory: nil,
            url: nil
        )

        verify(fullHandleService)
            .parse(.value("config-account/config-project"))
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func run_throws_when_full_handle_missing_from_argument_and_config() async throws {
        let (
            subject,
            _,
            _,
            _,
            _,
            configLoader,
            _,
            _
        ) = makeSubject()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(url: serverURL))

        await #expect(throws: CacheConfigCommandServiceError.missingFullHandle) {
            try await subject.run(
                fullHandle: nil,
                json: true,
                forceRefresh: false,
                directory: nil,
                url: nil
            )
        }
    }

    @Test(.withMockedEnvironment())
    func run_parses_full_handle_correctly() async throws {
        // Given
        let (
            subject,
            _,
            serverAuthenticationController,
            cacheURLStore,
            fullHandleService,
            _,
            _,
            _
        ) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("token"))

        // When
        try await subject.run(
            fullHandle: "my-account/my-project",
            json: true,
            forceRefresh: false,
            directory: nil,
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
