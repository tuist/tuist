import Foundation
import Mockable
import TuistSupport

@Mockable
public protocol ServerAuthenticationControlling: Sendable {
    func authenticationToken(serverURL: URL) throws -> AuthenticationToken?
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

enum ServerAuthenticationControllerError: FatalError {
    case invalidJWT(String)

    var description: String {
        switch self {
        case let .invalidJWT(token):
            return "The access token \(token) is invalid. Try to reauthenticate by running `tuist auth`."
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidJWT:
            return .bug
        }
    }
}

public final class ServerAuthenticationController: ServerAuthenticationControlling {
    private let credentialsStore: ServerCredentialsStoring
    private let ciChecker: CIChecking
    private let environment: Environmenting

    public init(
        credentialsStore: ServerCredentialsStoring = ServerCredentialsStore(),
        ciChecker: CIChecking = CIChecker(),
        environment: Environmenting = Environment.shared
    ) {
        self.credentialsStore = credentialsStore
        self.ciChecker = ciChecker
        self.environment = environment
    }

    public func authenticationToken(serverURL: URL) throws -> AuthenticationToken? {
        if ciChecker.isCI() {
            if let configToken = environment.tuistVariables[Constants.EnvironmentVariables.token] {
                return .project(configToken)
            } else if let deprecatedToken = environment.tuistVariables[Constants.EnvironmentVariables.deprecatedToken] {
                logger
                    .warning(
                        "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
                    )
                return .project(deprecatedToken)
            } else {
                return nil
            }
        } else {
            let credentials = try credentialsStore.read(serverURL: serverURL)
            return try credentials.map {
                if let refreshToken = $0.refreshToken {
                    return .user(
                        legacyToken: nil,
                        accessToken: try $0.accessToken.map(parseJWT),
                        refreshToken: try parseJWT(refreshToken)
                    )
                } else {
                    logger.warning("You are using a deprecated user token. Please, reauthenticate by running `tuist auth`.")
                    return .user(
                        legacyToken: $0.token,
                        accessToken: nil,
                        refreshToken: nil
                    )
                }
            }
        }
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
            expiryDate: Date(timeIntervalSince1970: TimeInterval(payload.exp))
        )
    }

    private struct JWTPayload: Codable {
        let exp: Int
    }
}
