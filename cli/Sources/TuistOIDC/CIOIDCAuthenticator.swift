#if canImport(TuistSupport)
    import Foundation
    import Mockable
    import TuistSupport

    enum OIDCCIProvider: String, CaseIterable {
        case githubActions

        var displayName: String {
            switch self {
            case .githubActions:
                "GitHub Actions"
            }
        }

        var oidcAudience: String {
            switch self {
            case .githubActions:
                "tuist"
            }
        }
    }

    @Mockable
    public protocol CIOIDCAuthenticating {
        func fetchOIDCToken() async throws -> String
    }

    enum CIOIDCAuthenticatorError: LocalizedError, Equatable {
        case unsupportedCIEnvironment
        case missingGitHubActionsOIDCPermissions

        var errorDescription: String? {
            switch self {
            case .unsupportedCIEnvironment:
                "OIDC authentication is not supported in this environment. " +
                    "Supported CI providers: GitHub Actions."
            case .missingGitHubActionsOIDCPermissions:
                "GitHub Actions OIDC token request variables not set. " +
                    "Ensure your workflow has 'permissions: id-token: write' set."
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

            throw CIOIDCAuthenticatorError.unsupportedCIEnvironment
        }

        // MARK: - GitHub Actions

        private var isGitHubActionsEnvironment: Bool {
            Environment.current.variables["GITHUB_ACTIONS"] == "true"
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
                audience: OIDCCIProvider.githubActions.oidcAudience
            )
        }
    }
#endif
