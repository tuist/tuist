import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol RefreshAuthTokenServicing: Sendable {
    func refreshTokens(
        serverURL: URL,
        refreshToken: String
    ) async throws -> ServerAuthenticationTokens
}

public enum RefreshAuthTokenServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case unauthorized(String)
    case badRequest

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CLI authentication failed due to an unknown Tuist response of \(statusCode)."
        case .badRequest:
            return "The CLI failed to refresh the token due to a bad request error."
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
        case .badRequest:
            throw RefreshAuthTokenServiceError.badRequest
        }
    }
}
