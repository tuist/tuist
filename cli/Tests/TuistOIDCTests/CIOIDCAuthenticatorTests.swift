import Foundation
import Mockable
import Testing
import TuistSupport
import TuistTesting

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
    func fetchOIDCToken_returns_bitrise_oidc_token() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "BITRISE_IO": "true",
            "BITRISE_OIDC_ID_TOKEN": "bitrise-oidc-token",
        ]

        // When
        let token = try await subject.fetchOIDCToken()

        // Then
        #expect(token == "bitrise-oidc-token")
    }
}
