import Foundation
import Mockable

#if canImport(TuistSupport)
    import TuistSupport
#endif

@Mockable
public protocol ServerAuthenticationControlling: Sendable {
    func authenticationToken(serverURL: URL) async throws -> AuthenticationToken?
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

public final class ServerAuthenticationController: ServerAuthenticationControlling {
    private let credentialsStore: ServerCredentialsStoring

    #if canImport(TuistSupport)
        public init(
            credentialsStore: ServerCredentialsStoring = ServerCredentialsStore()
        ) {
            self.credentialsStore = credentialsStore
        }
    #else
        public init(
            credentialsStore: ServerCredentialsStoring = ServerCredentialsStore()
        ) {
            self.credentialsStore = credentialsStore
        }
    #endif

    public func authenticationToken(serverURL: URL) async throws -> AuthenticationToken? {
        #if canImport(TuistSupport)
            if Environment.current.isCI {
                if let configToken = Environment.current.tuistVariables[
                    Constants.EnvironmentVariables.token
                ] {
                    return .project(configToken)
                } else if let deprecatedToken = Environment.current.tuistVariables[
                    Constants.EnvironmentVariables.deprecatedToken
                ] {
                    Logger.current
                        .warning(
                            "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
                        )
                    return .project(deprecatedToken)
                } else {
                    return nil
                }
            } else {
                var credentials: ServerCredentials? = try await credentialsStore.read(
                    serverURL: serverURL
                )
                if isTuistDevURL(serverURL), credentials == nil {
                    credentials = try await credentialsStore.read(
                        serverURL: URL(string: "https://cloud.tuist.io")!
                    )
                }
                return try credentials.map {
                    if let refreshToken = $0.refreshToken {
                        return .user(
                            legacyToken: nil,
                            accessToken: try $0.accessToken.map(parseJWT),
                            refreshToken: try parseJWT(refreshToken)
                        )
                    } else {
                        Logger.current
                            .warning(
                                "You are using a deprecated user token. Please, reauthenticate by running 'tuist auth login'."
                            )
                        return .user(
                            legacyToken: $0.token,
                            accessToken: nil,
                            refreshToken: nil
                        )
                    }
                }
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

    func isTuistDevURL(_ serverURL: URL) -> Bool {
        // URL fails if one of the URLs has a trailing slash and the other not.
        return serverURL.absoluteString.hasPrefix("https://tuist.dev")
    }

    private func parseJWT(_ jwt: String) throws -> JWT {
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

    private struct JWTPayload: Codable {
        let exp: Int
        let email: String?
        // swiftlint:disable:next identifier_name
        let preferred_username: String?
    }
}
