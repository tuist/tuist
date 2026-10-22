import Foundation
import TuistServer

/// Resolves the credential to send to cache nodes: a cache token exchanged for
/// the caller's credential when the server can mint one, and the credential
/// itself otherwise.
///
/// Cache nodes record the origin the exchanged token carries with the traffic
/// they serve, so every cache client, whatever its protocol, should send the
/// exchanged token.
public struct CacheCredentialProvider: Sendable {
    private let authenticationURL: URL
    private let fullHandle: String?
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let cacheTokenStore: CacheTokenStoring

    /// - Parameter fullHandle: The `account/project` the requests are for. Only
    ///   callers that name it exchange: the scope is what keeps the token small
    ///   enough for a header, so exchanging without one would risk a token
    ///   carrying every project an account-wide credential reaches.
    public init(
        authenticationURL: URL,
        fullHandle: String?,
        serverAuthenticationController: ServerAuthenticationControlling,
        cacheTokenStore: CacheTokenStoring = CacheTokenStore.shared
    ) {
        self.authenticationURL = authenticationURL
        self.fullHandle = fullHandle
        self.serverAuthenticationController = serverAuthenticationController
        self.cacheTokenStore = cacheTokenStore
    }

    /// Returns nil when there is no credential to send. Throws
    /// ``GetCacheTokenServiceError/freeTierExhausted(_:)`` when the account's
    /// plan bars it from the cache.
    public func credential() async throws -> String? {
        guard let token = try await serverAuthenticationController.authenticationToken(serverURL: authenticationURL) else {
            return nil
        }
        guard let fullHandle else { return token.value }
        return try await cacheTokenStore.cacheToken(
            authenticationURL: authenticationURL,
            fullHandle: fullHandle
        ) ?? token.value
    }
}
