import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol CIOIDCAuthenticating {
    func fetchOIDCToken() async throws -> String
}

enum CIOIDCAuthenticatorError: LocalizedError, Equatable {
    case unsupportedCIEnvironment
    case missingGitHubActionsOIDCPermissions
    case missingCircleCIOIDCToken
    case missingBitriseOIDCToken

    var errorDescription: String? {
        switch self {
        case .unsupportedCIEnvironment:
            "OIDC authentication is not supported in this environment. OIDC authentication is supported in the following CI providers: GitHub Actions, CircleCI, Bitrise."
        case .missingGitHubActionsOIDCPermissions:
            "GitHub Actions OIDC token request variables not set. Ensure your workflow has 'permissions: id-token: write' set."
        case .missingCircleCIOIDCToken:
            "CircleCI OIDC token not found. Ensure OIDC is enabled for your CircleCI project in the project settings."
        case .missingBitriseOIDCToken:
            "Bitrise OIDC token not found. Ensure you have added the 'Get OIDC Identity Token' step before this step in your workflow."
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

        return try await oidcTokenFetcher.fetchToken(
            requestURL: requestURL,
            requestToken: requestToken,
            audience: "tuist"
        )
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
        guard let token = Environment.current.variables["BITRISE_OIDC_ID_TOKEN"] else {
            throw CIOIDCAuthenticatorError.missingBitriseOIDCToken
        }

        return token
    }
}
