import Foundation
import Mockable

#if canImport(TuistSupport)
    import TuistSupport
#endif

@Mockable
public protocol ServerAuthenticationControlling: Sendable {
    @discardableResult func authenticationToken(serverURL: URL) async throws
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

enum ServerAuthenticationControllerError: LocalizedError {
    case invalidJWT(String)

    var errorDescription: String? {
        switch self {
        case let .invalidJWT(token):
            return
                "The access token \(token) is invalid. Try to reauthenticate by running 'tuist auth login'."
        }
    }
}

public struct ServerAuthenticationController: ServerAuthenticationControlling {
    private let credentialsStore: ServerCredentialsStoring
    private let cachedValueStore: CachedValueStoring
    private let refreshAuthTokenService: RefreshAuthTokenServicing

    public init(
        credentialsStore: ServerCredentialsStoring = ServerCredentialsStore(),
        refreshAuthTokenService: RefreshAuthTokenServicing = RefreshAuthTokenService()
    ) {
        self.init(
            credentialsStore: ServerCredentialsStore(),
            cachedValueStore: CachedValueStore.shared,
            refreshAuthTokenService: RefreshAuthTokenService()
        )
    }

    init(
        credentialsStore: ServerCredentialsStoring,
        cachedValueStore: CachedValueStoring,
        refreshAuthTokenService: RefreshAuthTokenServicing
    ) {
        self.credentialsStore = credentialsStore
        self.cachedValueStore = cachedValueStore
        self.refreshAuthTokenService = refreshAuthTokenService
    }

    @discardableResult public func authenticationToken(serverURL: URL)
        async throws -> AuthenticationToken?
    {
        #if canImport(TuistSupport)
            if Environment.current.isCI {
                return try await ciAuthenticationToken()
            } else {
                return try await cliManagedAuthenticationTokenRefreshingIfNeeded(
                    serverURL: serverURL, forceRefresh: false
                )
            }
        #else
            return .user(
                legacyToken: nil,
                accessToken: JWT(
                    token: "INSERT_HERE",
                    expiryDate: Date(timeIntervalSinceNow: 10000),
                    email: nil,
                    preferredUsername: nil
                ),
                refreshToken: nil
            )
        #endif
    }

    public func refreshToken(serverURL: URL) async throws {
        try await cliManagedAuthenticationTokenRefreshingIfNeeded(serverURL: serverURL, forceRefresh: true)
    }

    @discardableResult private func cliManagedAuthenticationTokenRefreshingIfNeeded(
        serverURL: URL,
        forceRefresh: Bool
    ) async throws
        -> AuthenticationToken?
    {
        return
            try await cachedValueStore
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
                                Logger.current.debug(
                                    "Access token expires in less than \(expiresIn) seconds. Renewing..."
                                )
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
                                    accessToken: try Self.parseJWT(tokens.accessToken),
                                    refreshToken: try Self.parseJWT(tokens.refreshToken)
                                )
                                expiresAt = try ServerAuthenticationController.parseJWT(
                                    tokens.accessToken
                                )
                                .expiryDate
                            } else {
                                upToDateToken = .user(
                                    legacyToken: nil, accessToken: accessToken,
                                    refreshToken: refreshToken
                                )
                                expiresAt = accessToken.expiryDate
                            }
                        } else {
                            throw ServerClientAuthenticationError.notAuthenticated
                        }
                    }
                    return (value: upToDateToken, expiresAt: expiresAt)
                }
    }

    private func fetchTokenFromStore(serverURL: URL) async throws -> AuthenticationToken? {
        var credentials: ServerCredentials? = try await credentialsStore.read(
            serverURL: serverURL
        )
        return try credentials.map {
            if let refreshToken = $0.refreshToken {
                return .user(
                    legacyToken: nil,
                    accessToken: try $0.accessToken.map(Self.parseJWT),
                    refreshToken: try Self.parseJWT(refreshToken)
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

    static func parseJWT(_ jwt: String) throws -> JWT {
        let components = jwt.components(separatedBy: ".")
        guard components.count == 3
        else {
            throw ServerAuthenticationControllerError.invalidJWT(jwt)
        }
        let jwtEncodedPayload = components[1]
        let remainder = jwtEncodedPayload.count % 4
        let paddedJWTEncodedPayload: String
        if remainder > 0 {
            paddedJWTEncodedPayload = jwtEncodedPayload.padding(
                toLength: jwtEncodedPayload.count + 4 - remainder,
                withPad: "=",
                startingAt: 0
            )
        } else {
            paddedJWTEncodedPayload = jwtEncodedPayload
        }
        guard let data = Data(base64Encoded: paddedJWTEncodedPayload)
        else {
            throw ServerAuthenticationControllerError.invalidJWT(jwtEncodedPayload)
        }
        let jsonDecoder = JSONDecoder()
        let payload = try jsonDecoder.decode(JWTPayload.self, from: data)

        return JWT(
            token: jwt,
            expiryDate: Date(timeIntervalSince1970: TimeInterval(payload.exp)),
            email: payload.email,
            preferredUsername: payload.preferred_username
        )
    }

    static func encodeJWT(_ jwt: JWT) throws -> String {
        // Create header (typically static for most JWTs)
        let header = [
            "alg": "HS256", // or whatever algorithm you're using
            "typ": "JWT",
        ]

        // Create payload
        let payload = JWTPayload(
            exp: Int(jwt.expiryDate.timeIntervalSince1970),
            email: jwt.email,
            preferred_username: jwt.preferredUsername
            // Add any other fields your JWTPayload has
        )

        // Encode header
        let jsonEncoder = JSONEncoder()
        let headerData = try jsonEncoder.encode(header)
        let headerBase64 = headerData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // Encode payload
        let payloadData = try jsonEncoder.encode(payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // For a complete JWT, you'd need to sign it with a secret key
        // This is a simplified version that creates an unsigned token
        let unsignedToken = "\(headerBase64).\(payloadBase64)"

        // In a real implementation, you'd create a signature here
        // let signature = createSignature(unsignedToken, secret: secretKey)
        // return "\(unsignedToken).\(signature)"

        // For now, returning unsigned token with empty signature
        return "\(unsignedToken)."
    }

    private struct JWTPayload: Codable {
        let exp: Int
        let email: String?
        // swiftlint:disable:next identifier_name
        let preferred_username: String?
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
            try await credentialsStore
                .store(
                    credentials: ServerCredentials(
                        token: nil,
                        accessToken: newTokens.accessToken,
                        refreshToken: newTokens.refreshToken
                    ),
                    serverURL: serverURL
                )
            return newTokens
        } catch {
            throw ServerClientAuthenticationError.notAuthenticated
        }
    }
}
