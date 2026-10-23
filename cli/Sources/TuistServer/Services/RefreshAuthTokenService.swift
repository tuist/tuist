import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol RefreshAuthTokenServicing: Sendable {
    func refreshTokens(
        serverURL: URL,
        refreshToken: String
    ) async throws -> ServerAuthenticationTokens
}

public enum RefreshAuthTokenServiceError: LocalizedError, Equatable, HTTPStatusCodeError {
    case unknownError(Int)
    case unauthorized(String)
    case badRequest

    public var httpStatusCode: Int {
        switch self {
        case let .unknownError(statusCode): statusCode
        case .unauthorized: 401
        case .badRequest: 400
        }
    }

    /// Only a status the server can resolve on its own is worth refreshing again for: a rejected or malformed refresh
    /// is answered the same way every time.
    public var isRetryable: Bool {
        guard case let .unknownError(statusCode) = self else { return false }
        return statusCode == 408 || statusCode == 429 || (500 ..< 600).contains(statusCode)
    }

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

public struct RefreshAuthTokenService: RefreshAuthTokenServicing {
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
