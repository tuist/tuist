import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol RefreshAuthTokenServicing: Sendable {
    func refreshTokens(
        serverURL: URL,
        refreshToken: String
    ) async throws -> ServerAuthenticationTokens
}

public enum RefreshAuthTokenServiceError: FatalError, Equatable {
    case unknownError(Int)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The CLI authentication failed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        }
    }
}

public final class RefreshAuthTokenService: RefreshAuthTokenServicing {
    public init() {}

    public func refreshTokens(
        serverURL: URL,
        refreshToken: String
    ) async throws -> ServerAuthenticationTokens {
        let client = Client.unauthenticated(serverURL: serverURL)

        let response = try await client.refreshToken(
            .init(body: .json(.init(refresh_token: refreshToken)))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(tokens):
                return ServerAuthenticationTokens(accessToken: tokens.access_token, refreshToken: tokens.refresh_token)
            }
        case let .unauthorized(unauthorizedResponse):
            switch unauthorizedResponse.body {
            case let .json(error):
                throw RefreshAuthTokenServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw RefreshAuthTokenServiceError.unknownError(statusCode)
        }
    }
}
