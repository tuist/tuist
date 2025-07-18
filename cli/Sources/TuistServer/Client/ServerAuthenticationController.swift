import Foundation
import Mockable
import OpenAPIRuntime

#if canImport(TuistSupport)
    import TuistSupport
#endif

@Mockable
public protocol ServerAuthenticationControlling: Sendable {
    func authenticationToken(serverURL: URL) async throws
        -> AuthenticationToken?
    func refreshToken(serverURL: URL) async throws
}

public enum AuthenticationToken: CustomStringConvertible, Equatable {
    /// The token represents a user session. User sessions are typically used in
    /// local environments where the user can be guided through an interactive
    /// authentication workflow
    case user(legacyToken: String?, accessToken: JWT?, refreshToken: JWT?)

    /// The token represents a project session. Project sessions are typically used
    /// in CI environments where limited scopes are desired for security reasons.
    case project(String)

    /// It returns the value of the token
    public var value: String {
        switch self {
        case let .user(legacyToken: legacyToken, accessToken: accessToken, refreshToken: _):
            if let accessToken {
                return accessToken.token
            } else {
                return legacyToken!
            }
        case let .project(token):
            return token
        }
    }

    public var description: String {
        switch self {
        case .user:
            return "tuist user token: \(value)"
        case let .project(token):
            return "tuist project token: \(token)"
        }
    }
}

public struct ServerAuthenticationController: ServerAuthenticationControlling {
    private let refreshAuthTokenService: RefreshAuthTokenServicing

    public init(
        refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService()
    ) {
        self.refreshAuthTokenService = refreshAuthTokenService
    }

    @discardableResult public func authenticationToken(serverURL: URL)
        async throws -> AuthenticationToken?
    {
        #if canImport(TuistSupport)
            if Environment.current.isCI {
                return try await ciAuthenticationToken()
            } else {
                return try await authenticationTokenRefreshingIfNeeded(
                    serverURL: serverURL, forceRefresh: false
                )
            }
        #else
            return try await authenticationTokenRefreshingIfNeeded(
                serverURL: serverURL, forceRefresh: false
            )
        #endif
    }

    public func refreshToken(serverURL: URL) async throws {
        try await authenticationTokenRefreshingIfNeeded(
            serverURL: serverURL, forceRefresh: true
        )
    }

    @discardableResult private func authenticationTokenRefreshingIfNeeded(
        serverURL: URL,
        forceRefresh: Bool
    ) async throws
        -> AuthenticationToken?
    {
        #if canImport(TuistSupport)
            Logger.current.debug("Refreshing authentication token for \(serverURL) if needed")
        #endif
        return
            try await CachedValueStore.current
                .getValue(key: "token_\(serverURL.absoluteString)") {
                    () -> (value: AuthenticationToken, expiresAt: Date?)? in
                    guard let token = try await fetchTokenFromStore(serverURL: serverURL) else {
                        return nil
                    }

                    let upToDateToken: AuthenticationToken
                    var expiresAt: Date?

                    switch token {
                    case .project:
                        upToDateToken = token
                    case let .user(
                        legacyToken: legacyToken, accessToken: accessToken, refreshToken: refreshToken
                    ):
                        if legacyToken != nil {
                            upToDateToken = token
                        } else if let accessToken {
                            // We consider a token to be expired if the expiration date is in the past or 30 seconds from now
                            let now = Date.now()
                            let expiresIn = accessToken.expiryDate
                                .timeIntervalSince(now)
                            let refresh = expiresIn < 30 || forceRefresh

                            #if canImport(TuistSupport)
                                if refresh {
                                    Logger.current.debug(
                                        "Access token expires in less than \(expiresIn) seconds. Renewing..."
                                    )
                                } else {
                                    Logger.current.debug(
                                        "Access token expires in \(expiresIn) seconds and it is still valid"
                                    )
                                }
                            #endif
                            if refresh {
                                guard let refreshToken else {
                                    throw ServerClientAuthenticationError.notAuthenticated
                                }
                                #if canImport(TuistSupport)
                                    Logger.current.debug("Refreshing access token for \(serverURL)")
                                #endif
                                let tokens = try await refreshTokens(
                                    serverURL: serverURL, refreshToken: refreshToken
                                )
                                #if canImport(TuistSupport)
                                    Logger.current.debug("Access token refreshed for \(serverURL)")
                                #endif
                                upToDateToken = .user(
                                    legacyToken: nil,
                                    accessToken: try JWT.parse(tokens.accessToken),
                                    refreshToken: try JWT.parse(tokens.refreshToken)
                                )
                                expiresAt = try JWT.parse(tokens.accessToken)
                                    .expiryDate
                            } else {
                                upToDateToken = .user(
                                    legacyToken: nil, accessToken: accessToken,
                                    refreshToken: refreshToken
                                )
                                expiresAt = accessToken.expiryDate
                            }
                        } else {
                            try await ServerCredentialsStore.current.delete(serverURL: serverURL)
                            throw ServerClientAuthenticationError.notAuthenticated
                        }
                    }
                    return (value: upToDateToken, expiresAt: expiresAt)
                }
    }

    private func fetchTokenFromStore(serverURL: URL) async throws -> AuthenticationToken? {
        let credentials: ServerCredentials? = try await ServerCredentialsStore.current.read(
            serverURL: serverURL
        )
        return try credentials.map {
            if let refreshToken = $0.refreshToken {
                return .user(
                    legacyToken: nil,
                    accessToken: try $0.accessToken.map(JWT.parse),
                    refreshToken: try JWT.parse(refreshToken)
                )
            } else {
                #if canImport(TuistSupport)
                    Logger.current
                        .warning(
                            "You are using a deprecated user token. Please, reauthenticate by running 'tuist auth login'."
                        )
                #endif
                return .user(
                    legacyToken: $0.token,
                    accessToken: nil,
                    refreshToken: nil
                )
            }
        }
    }

    private func ciAuthenticationToken() async throws -> AuthenticationToken? {
        #if canImport(TuistSupport)
            if let configToken = Environment.current.tuistVariables[
                Constants.EnvironmentVariables.token
            ] {
                return .project(configToken)
            } else if let deprecatedToken = Environment.current.tuistVariables[
                "TUIST_CONFIG_CLOUD_TOKEN"
            ] {
                AlertController.current
                    .warning(
                        .alert(
                            "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
                        )
                    )
                return .project(deprecatedToken)
            } else {
                return nil
            }
        #else
            return nil
        #endif
    }

    func isTuistDevURL(_ serverURL: URL) -> Bool {
        // URL fails if one of the URLs has a trailing slash and the other not.
        return serverURL.absoluteString.hasPrefix("https://tuist.dev")
    }

    private func refreshTokens(
        serverURL: URL,
        refreshToken: JWT
    ) async throws -> ServerAuthenticationTokens {
        do {
            let newTokens = try await RetryProvider()
                .runWithRetries {
                    return try await refreshAuthTokenService.refreshTokens(
                        serverURL: serverURL,
                        refreshToken: refreshToken.token
                    )
                }
            try await ServerCredentialsStore.current
                .store(
                    credentials: ServerCredentials(
                        token: nil,
                        accessToken: newTokens.accessToken,
                        refreshToken: newTokens.refreshToken
                    ),
                    serverURL: serverURL
                )
            return newTokens
        } catch let error as ClientError {
            let underlyingError = error.underlyingError as NSError
            switch URLError.Code(rawValue: underlyingError.code) {
            case .notConnectedToInternet:
                throw error
            default:
                throw ServerClientAuthenticationError.notAuthenticated
            }
        } catch {
            throw ServerClientAuthenticationError.notAuthenticated
        }
    }
}
