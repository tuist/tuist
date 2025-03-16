import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol AuthenticateServicing {
    func authenticate(
        email: String,
        password: String,
        serverURL: URL
    ) async throws -> ServerAuthenticationTokens
}

enum AuthenticateServiceError: FatalError {
    case unknownError(Int)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We failed to authenticate you due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        }
    }
}

public final class AuthenticateService: AuthenticateServicing {
    public init() {}

    public func authenticate(
        email: String,
        password: String,
        serverURL: URL
    ) async throws -> ServerAuthenticationTokens {
        let client = Client.unauthenticated(serverURL: serverURL)

        let response = try await client.authenticate(
            .init(
                body: .json(
                    .init(
                        email: email,
                        password: password
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(authenticationTokens):
                return ServerAuthenticationTokens(
                    accessToken: authenticationTokens.access_token,
                    refreshToken: authenticationTokens.refresh_token
                )
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw AuthenticateServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw AuthenticateServiceError.unknownError(statusCode)
        }
    }
}
