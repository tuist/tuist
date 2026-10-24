import Foundation
import Mockable

#if canImport(TuistOIDC)
    import TuistOIDC
#endif

/// Renews account tokens that `tuist auth login` obtained by exchanging a CI provider's OIDC token.
/// Those tokens carry no refresh token, so the only way to renew one is to mint a new OIDC token and
/// exchange it again.
@Mockable
public protocol OIDCAccountTokenRefreshing: Sendable {
    /// Whether the current environment can mint a new OIDC token to exchange.
    func canRefreshAccountToken() -> Bool

    /// Mints a new OIDC token and exchanges it for a new account access token.
    func refreshAccountToken(serverURL: URL) async throws -> String
}

public struct OIDCAccountTokenRefresher: OIDCAccountTokenRefreshing {
    #if canImport(TuistOIDC)
        private let ciOIDCAuthenticator: CIOIDCAuthenticating
        private let exchangeOIDCTokenService: ExchangeOIDCTokenServicing

        public init(
            ciOIDCAuthenticator: CIOIDCAuthenticating = CIOIDCAuthenticator(),
            exchangeOIDCTokenService: ExchangeOIDCTokenServicing = ExchangeOIDCTokenService()
        ) {
            self.ciOIDCAuthenticator = ciOIDCAuthenticator
            self.exchangeOIDCTokenService = exchangeOIDCTokenService
        }

        public func canRefreshAccountToken() -> Bool {
            ciOIDCAuthenticator.canFetchFreshOIDCToken()
        }

        public func refreshAccountToken(serverURL: URL) async throws -> String {
            let oidcToken = try await ciOIDCAuthenticator.fetchOIDCToken()
            return try await exchangeOIDCTokenService.exchangeOIDCToken(
                oidcToken: oidcToken,
                serverURL: serverURL
            )
        }
    #else
        public init() {}

        public func canRefreshAccountToken() -> Bool {
            false
        }

        public func refreshAccountToken(serverURL _: URL) async throws -> String {
            throw ClientAuthenticationError.notAuthenticated
        }
    #endif
}
