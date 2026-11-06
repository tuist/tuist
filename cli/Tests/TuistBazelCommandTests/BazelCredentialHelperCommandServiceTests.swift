import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer
import TuistTesting

@testable import TuistBazelCommand

struct BazelCredentialHelperCommandServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!

    private func makeSubject(
        cacheToken: String = "scoped-cache-token", cacheTokenError: GetCacheTokenServiceError? = nil,
        fullHandle: String? = "account/project",
        expiresIn: Int = 1800,
        date: @escaping () -> Date = { Date() }
    ) -> (
        subject: BazelCredentialHelperCommandService,
        serverAuthenticationController: MockServerAuthenticationControlling
    ) {
        let serverEnvironmentService = MockServerEnvironmentServicing()
        let serverAuthenticationController = MockServerAuthenticationControlling()
        let configLoader = MockConfigLoading()
        let tokenService = MockGetCacheTokenServicing()
        if let cacheTokenError {
            given(tokenService).getCacheToken(serverURL: .any, fullHandle: .value(fullHandle))
                .willThrow(cacheTokenError)
        } else {
            given(tokenService).getCacheToken(serverURL: .any, fullHandle: .value(fullHandle))
                .willReturn(CacheToken(token: cacheToken, expiresIn: expiresIn))
        }

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(fullHandle: fullHandle, url: serverURL))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        let subject = BazelCredentialHelperCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            configLoader: configLoader,
            getCacheTokenService: tokenService,
            date: date
        )

        return (subject, serverAuthenticationController)
    }

    @Test(.withMockedEnvironment(), arguments: [404, 503])
    func credentials_propagates_exchange_failure(status: Int) async throws {
        let error = GetCacheTokenServiceError.unknownError(status)
        let (subject, authentication) = makeSubject(cacheTokenError: error)
        given(authentication).authenticationToken(serverURL: .any).willReturn(.project("raw-token"))
        await #expect(throws: error) {
            try await subject.credentials(helperCommand: "get", directory: nil)
        }
    }

    @Test(.withMockedEnvironment())
    func credentials_exchanges_a_cache_token_without_a_project_handle() async throws {
        let (subject, authentication) = makeSubject(fullHandle: nil)
        given(authentication).authenticationToken(serverURL: .any).willReturn(.project("raw-token"))
        let response = try await subject.credentials(helperCommand: "get", directory: nil)
        #expect(response.headers == ["Authorization": ["Bearer scoped-cache-token"]])
        #expect(response.expires != nil)
    }

    @Test(.withMockedEnvironment(), arguments: [0, 30, 60])
    func short_lived_tokens_are_not_cached_beyond_the_safety_margin(expiresIn: Int) async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let (subject, authentication) = makeSubject(expiresIn: expiresIn, date: { now })
        given(authentication).authenticationToken(serverURL: .any).willReturn(.project("raw-token"))
        let response = try await subject.credentials(helperCommand: "get", directory: nil)
        #expect(response.expires == ISO8601DateFormatter().string(from: now))
    }

    @Test(.withMockedEnvironment())
    func credentials_return_a_scoped_cache_token_with_bounded_expiry() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let (subject, authentication) = makeSubject(cacheToken: "scoped-cache-token", date: { now })
        given(authentication).authenticationToken(serverURL: .any).willReturn(.project("raw-token"))
        let response = try await subject.credentials(helperCommand: "get", directory: nil)
        #expect(response.headers == ["Authorization": ["Bearer scoped-cache-token"]])
        #expect(response.expires == ISO8601DateFormatter().string(from: now.addingTimeInterval(1740)))
    }

    @Test(.withMockedEnvironment())
    func credentials_returns_authorization_header_and_expiry_for_user_tokens() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject(
            date: { Date(timeIntervalSince1970: 1_750_000_000 - 3600) }
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        token: "access-token",
                        expiryDate: Date(timeIntervalSince1970: 1_750_000_000)
                    ),
                    refreshToken: .test(token: "refresh-token")
                )
            )

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        // The reported expiry is brought forward by the 60s safety margin so Bazel
        // re-invokes the helper before the token is actually rejected by the server.
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer scoped-cache-token"]],
                expires: "2025-06-15T14:35:40Z"
            )
        )
        verify(serverAuthenticationController)
            .refreshToken(serverURL: .value(serverURL))
            .called(0)
    }

    @Test(.withMockedEnvironment())
    func credentials_returns_cache_token_expiry_for_project_tokens() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject(
            date: { Date(timeIntervalSince1970: 1_750_000_000 - 3600) }
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(.project("project-token"))

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer scoped-cache-token"]],
                expires: "2025-06-15T14:35:40Z"
            )
        )
    }

    @Test(.withMockedEnvironment())
    func credentials_returns_expiry_for_account_tokens() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject(
            date: { Date(timeIntervalSince1970: 1_750_000_000 - 3600) }
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .account(
                    .test(
                        token: "account-token",
                        expiryDate: Date(timeIntervalSince1970: 1_750_000_000)
                    )
                )
            )

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        // Report the exchanged cache token lifetime, independent of the account credential expiry.
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer scoped-cache-token"]],
                expires: "2025-06-15T14:35:40Z"
            )
        )
    }

    @Test(.withMockedEnvironment())
    func credentials_throws_when_the_command_is_not_get() async throws {
        // Given
        let (subject, _) = makeSubject()

        // When/Then
        await #expect(throws: BazelCredentialHelperCommandServiceError.unsupportedCommand("store")) {
            try await subject.credentials(helperCommand: "store", directory: nil)
        }
    }

    @Test(.withMockedEnvironment())
    func credentials_throws_when_not_authenticated() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(nil)

        // When/Then
        await #expect(throws: BazelCredentialHelperCommandServiceError.notAuthenticated) {
            try await subject.credentials(helperCommand: "get", directory: nil)
        }
    }
}
