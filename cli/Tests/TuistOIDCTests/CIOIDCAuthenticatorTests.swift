import Foundation
import Mockable
import Testing
import TuistSupport
import TuistTesting

@testable import TuistOIDC

struct CIOIDCAuthenticatorTests {
    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_unsupportedCIEnvironment_when_not_in_github_actions() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        let subject = CIOIDCAuthenticator()

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.unsupportedCIEnvironment) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_missingGitHubActionsOIDCPermissions_when_request_url_missing() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "some-token",
        ]
        let subject = CIOIDCAuthenticator()

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.missingGitHubActionsOIDCPermissions) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_missingGitHubActionsOIDCPermissions_when_request_token_missing() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://token.actions.githubusercontent.com",
        ]
        let subject = CIOIDCAuthenticator()

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.missingGitHubActionsOIDCPermissions) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_when_token_fetcher_fails() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://token.actions.githubusercontent.com",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "some-token",
        ]
        let mockOIDCTokenFetcher = MockOIDCTokenFetching()
        given(mockOIDCTokenFetcher)
            .fetchToken(requestURL: .any, requestToken: .any, audience: .any)
            .willThrow(OIDCTokenFetcherError.tokenRequestFailed)

        let subject = CIOIDCAuthenticator(oidcTokenFetcher: mockOIDCTokenFetcher)

        // When / Then
        await #expect(throws: OIDCTokenFetcherError.tokenRequestFailed) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_returns_token_on_success() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://token.actions.githubusercontent.com",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "some-token",
        ]

        let expectedToken = "oidc-token-value"
        let mockOIDCTokenFetcher = MockOIDCTokenFetching()
        given(mockOIDCTokenFetcher)
            .fetchToken(requestURL: .any, requestToken: .any, audience: .any)
            .willReturn(expectedToken)

        let subject = CIOIDCAuthenticator(oidcTokenFetcher: mockOIDCTokenFetcher)

        // When
        let token = try await subject.fetchOIDCToken()

        // Then
        #expect(token == expectedToken)
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_passes_correct_parameters_to_fetcher() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        let expectedRequestURL = "https://token.actions.githubusercontent.com/token"
        let expectedRequestToken = "my-request-token"
        mockEnvironment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_URL": expectedRequestURL,
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": expectedRequestToken,
        ]

        let mockOIDCTokenFetcher = MockOIDCTokenFetching()
        given(mockOIDCTokenFetcher)
            .fetchToken(
                requestURL: .value(expectedRequestURL),
                requestToken: .value(expectedRequestToken),
                audience: .value("tuist")
            )
            .willReturn("token")

        let subject = CIOIDCAuthenticator(oidcTokenFetcher: mockOIDCTokenFetcher)

        // When
        _ = try await subject.fetchOIDCToken()

        // Then
        verify(mockOIDCTokenFetcher)
            .fetchToken(
                requestURL: .value(expectedRequestURL),
                requestToken: .value(expectedRequestToken),
                audience: .value("tuist")
            )
            .called(1)
    }
}
