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
        /// Attempts to fetch an OIDC token from the detected CI provider.
        /// Throws an error if not running in a supported CI environment or if token fetch fails.
        func fetchOIDCToken() async throws -> String
    }

    enum CIOIDCAuthenticatorError: LocalizedError {
        case unsupportedCIEnvironment
        case missingGitHubActionsOIDCPermissions
        case invalidGitHubActionsTokenRequestURL
        case gitHubActionsTokenRequestFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedCIEnvironment:
                "OIDC authentication is not supported in this environment. " +
                    "Supported CI providers: GitHub Actions."
            case .missingGitHubActionsOIDCPermissions:
                "GitHub Actions OIDC token request variables not set. " +
                    "Ensure your workflow has 'permissions: id-token: write' set."
            case .invalidGitHubActionsTokenRequestURL:
                "Invalid GitHub Actions OIDC token request URL."
            case .gitHubActionsTokenRequestFailed:
                "Failed to fetch OIDC token from GitHub Actions."
            }
        }
    }

    public struct CIOIDCAuthenticator: CIOIDCAuthenticating {
        public init() {}

        public func fetchOIDCToken() async throws -> String {
            // Try GitHub Actions
            if isGitHubActionsEnvironment {
                return try await fetchGitHubActionsOIDCToken()
            }

            // Add more CI providers here as needed

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

            guard var urlComponents = URLComponents(string: requestURL) else {
                throw CIOIDCAuthenticatorError.invalidGitHubActionsTokenRequestURL
            }

            var queryItems = urlComponents.queryItems ?? []
            queryItems.append(URLQueryItem(name: "audience", value: OIDCCIProvider.githubActions.oidcAudience))
            urlComponents.queryItems = queryItems

            guard let url = urlComponents.url else {
                throw CIOIDCAuthenticatorError.invalidGitHubActionsTokenRequestURL
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                throw CIOIDCAuthenticatorError.gitHubActionsTokenRequestFailed
            }

            struct OIDCTokenResponse: Decodable {
                let value: String
            }

            let tokenResponse = try JSONDecoder().decode(OIDCTokenResponse.self, from: data)
            return tokenResponse.value
        }
    }
#endif
