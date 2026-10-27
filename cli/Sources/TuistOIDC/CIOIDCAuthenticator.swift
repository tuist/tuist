import Foundation
import Mockable
import TuistEnvironment

@Mockable
public protocol CIOIDCAuthenticating: Sendable {
    func fetchOIDCToken() async throws -> String

    /// Whether the CI provider can mint a new OIDC token on demand during the job, as opposed to
    /// exposing a single token issued when the job started.
    func canFetchFreshOIDCToken() -> Bool
}

enum CIOIDCAuthenticatorError: LocalizedError, Equatable {
    case unsupportedCIEnvironment
    case emptyOIDCToken
    case missingGitHubActionsOIDCPermissions
    case gitHubActionsOIDCTokenRequestFailed(statusCode: Int, body: String)
    case missingCircleCIOIDCToken
    case missingBitriseOIDCToken

    var errorDescription: String? {
        switch self {
        case .unsupportedCIEnvironment:
            return "OIDC authentication is not supported in this environment. Use GitHub Actions, CircleCI, Bitrise, or supply a workload identity token through TUIST_OIDC_TOKEN."
        case .emptyOIDCToken:
            return "TUIST_OIDC_TOKEN is empty. Fetch an OIDC token with audience 'tuist' from your workload identity provider."
        case .missingGitHubActionsOIDCPermissions:
            return "GitHub Actions OIDC token request variables not set. Ensure your workflow has 'permissions: id-token: write' set."
        case let .gitHubActionsOIDCTokenRequestFailed(statusCode, body):
            let response = body.isEmpty ? "" : " Response: \(body)"
            return "GitHub Actions returned status code \(statusCode) while issuing an OIDC token. This usually indicates an upstream GitHub Actions OIDC outage or a transient runner networking issue. \(response)"
        case .missingCircleCIOIDCToken:
            return "CircleCI OIDC token not found. Ensure OIDC is enabled for your CircleCI project in the project settings."
        case .missingBitriseOIDCToken:
            return "Bitrise OIDC token not found. Ensure you have added the 'Get OIDC Identity Token' step before this step in your workflow."
        }
    }
}

public struct CIOIDCAuthenticator: CIOIDCAuthenticating {
    private let oidcTokenFetcher: OIDCTokenFetching

    public init() {
        oidcTokenFetcher = OIDCTokenFetcher()
    }

    init(oidcTokenFetcher: OIDCTokenFetching) {
        self.oidcTokenFetcher = oidcTokenFetcher
    }

    public func fetchOIDCToken() async throws -> String {
        if let token = Environment.current.variables["TUIST_OIDC_TOKEN"] {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedToken.isEmpty else {
                throw CIOIDCAuthenticatorError.emptyOIDCToken
            }
            return trimmedToken
        }

        if isGitHubActionsEnvironment {
            return try await fetchGitHubActionsOIDCToken()
        }

        if isCircleCIEnvironment {
            return try circleCIOIDCToken()
        }

        if isBitriseEnvironment {
            return try bitriseOIDCToken()
        }

        throw CIOIDCAuthenticatorError.unsupportedCIEnvironment
    }

    public func canFetchFreshOIDCToken() -> Bool {
        isGitHubActionsEnvironment
            && Environment.current.variables["ACTIONS_ID_TOKEN_REQUEST_URL"] != nil
            && Environment.current.variables["ACTIONS_ID_TOKEN_REQUEST_TOKEN"] != nil
    }

    // MARK: - GitHub Actions

    private var isGitHubActionsEnvironment: Bool {
        Environment.current.isVariableTruthy("GITHUB_ACTIONS")
    }

    private func fetchGitHubActionsOIDCToken() async throws -> String {
        guard let requestURL = Environment.current.variables["ACTIONS_ID_TOKEN_REQUEST_URL"],
              let requestToken = Environment.current.variables["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
        else {
            throw CIOIDCAuthenticatorError.missingGitHubActionsOIDCPermissions
        }

        do {
            return try await oidcTokenFetcher.fetchToken(
                requestURL: requestURL,
                requestToken: requestToken,
                audience: "tuist"
            )
        } catch let error as OIDCTokenFetcherError {
            switch error {
            case let .tokenRequestFailed(statusCode, body):
                throw CIOIDCAuthenticatorError.gitHubActionsOIDCTokenRequestFailed(
                    statusCode: statusCode,
                    body: body
                )
            case .invalidTokenRequestURL:
                throw error
            }
        }
    }

    // MARK: - CircleCI

    private var isCircleCIEnvironment: Bool {
        Environment.current.isVariableTruthy("CIRCLECI")
    }

    private func circleCIOIDCToken() throws -> String {
        guard let token = Environment.current.variables["CIRCLE_OIDC_TOKEN_V2"]
            ?? Environment.current.variables["CIRCLE_OIDC_TOKEN"]
        else {
            throw CIOIDCAuthenticatorError.missingCircleCIOIDCToken
        }

        return token
    }

    // MARK: - Bitrise

    private var isBitriseEnvironment: Bool {
        Environment.current.isVariableTruthy("BITRISE_IO")
    }

    private func bitriseOIDCToken() throws -> String {
        guard let token = Environment.current.variables["BITRISE_OIDC_ID_TOKEN"]
            ?? Environment.current.variables["BITRISE_IDENTITY_TOKEN"]
        else {
            throw CIOIDCAuthenticatorError.missingBitriseOIDCToken
        }

        return token
    }
}
