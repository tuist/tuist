import Foundation
import Mockable
import Testing
import TuistEnvironment
import TuistEnvironmentTesting

@testable import TuistOIDC

struct CIOIDCAuthenticatorTests {
    private let oidcTokenFetcher: MockOIDCTokenFetching
    private let subject: CIOIDCAuthenticator

    init() {
        oidcTokenFetcher = MockOIDCTokenFetching()
        subject = CIOIDCAuthenticator(oidcTokenFetcher: oidcTokenFetcher)
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_unsupportedCIEnvironment_when_not_in_github_actions() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [:]

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.unsupportedCIEnvironment) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_missingGitHubActionsOIDCPermissions_when_request_url_missing() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "some-token",
        ]

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.missingGitHubActionsOIDCPermissions) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_missingGitHubActionsOIDCPermissions_when_request_token_missing() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://token.actions.githubusercontent.com",
        ]

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.missingGitHubActionsOIDCPermissions) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_returns_token_on_success() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://token.actions.githubusercontent.com",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "some-token",
        ]

        let expectedToken = "oidc-token-value"
        given(oidcTokenFetcher)
            .fetchToken(requestURL: .any, requestToken: .any, audience: .any)
            .willReturn(expectedToken)

        // When
        let token = try await subject.fetchOIDCToken()

        // Then
        #expect(token == expectedToken)
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_wraps_github_actions_request_failures() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITHUB_ACTIONS": "true",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://token.actions.githubusercontent.com",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "some-token",
        ]

        given(oidcTokenFetcher)
            .fetchToken(requestURL: .any, requestToken: .any, audience: .any)
            .willThrow(
                OIDCTokenFetcherError.tokenRequestFailed(
                    statusCode: 503,
                    body: "upstream connect error"
                )
            )

        // When / Then
        await #expect(
            throws: CIOIDCAuthenticatorError.gitHubActionsOIDCTokenRequestFailed(
                statusCode: 503,
                body: "upstream connect error"
            )
        ) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test
    func github_actions_request_failure_error_description_is_actionable() {
        let error = CIOIDCAuthenticatorError.gitHubActionsOIDCTokenRequestFailed(
            statusCode: 503,
            body: "upstream connect error"
        )

        #expect(error.localizedDescription.contains("GitHub Actions returned status code 503"))
        #expect(error.localizedDescription.contains("upstream GitHub Actions OIDC outage"))
        #expect(error.localizedDescription.contains("upstream connect error"))
    }

    // MARK: - CircleCI

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_missingCircleCIOIDCToken_when_token_missing() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "CIRCLECI": "true",
        ]

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.missingCircleCIOIDCToken) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_returns_circle_oidc_token_v2() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "CIRCLECI": "true",
            "CIRCLE_OIDC_TOKEN_V2": "circle-oidc-token-v2",
            "CIRCLE_OIDC_TOKEN": "circle-oidc-token",
        ]

        // When
        let token = try await subject.fetchOIDCToken()

        // Then
        #expect(token == "circle-oidc-token-v2")
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_returns_circle_oidc_token_when_v2_missing() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "CIRCLECI": "true",
            "CIRCLE_OIDC_TOKEN": "circle-oidc-token",
        ]

        // When
        let token = try await subject.fetchOIDCToken()

        // Then
        #expect(token == "circle-oidc-token")
    }

    // MARK: - Bitrise

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_throws_missingBitriseOIDCToken_when_token_missing() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "BITRISE_IO": "true",
        ]

        // When / Then
        await #expect(throws: CIOIDCAuthenticatorError.missingBitriseOIDCToken) {
            try await subject.fetchOIDCToken()
        }
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_returns_bitrise_oidc_id_token() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "BITRISE_IO": "true",
            "BITRISE_OIDC_ID_TOKEN": "bitrise-oidc-id-token",
            "BITRISE_IDENTITY_TOKEN": "bitrise-identity-token",
        ]

        // When
        let token = try await subject.fetchOIDCToken()

        // Then
        #expect(token == "bitrise-oidc-id-token")
    }

    @Test(.withMockedEnvironment())
    func fetchOIDCToken_returns_bitrise_identity_token_when_oidc_id_token_missing() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "BITRISE_IO": "true",
            "BITRISE_IDENTITY_TOKEN": "bitrise-identity-token",
        ]

        // When
        let token = try await subject.fetchOIDCToken()

        // Then
        #expect(token == "bitrise-identity-token")
    }
}
