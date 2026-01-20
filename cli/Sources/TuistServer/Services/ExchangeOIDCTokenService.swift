import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol ExchangeOIDCTokenServicing {
    func exchangeOIDCToken(oidcToken: String, serverURL: URL) async throws -> String
}

enum ExchangeOIDCTokenServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            "OIDC token exchange failed with status \(statusCode)."
        case let .unauthorized(message):
            message
        case let .forbidden(message):
            message
        }
    }
}

public struct ExchangeOIDCTokenService: ExchangeOIDCTokenServicing {
    public init() {}

    public func exchangeOIDCToken(oidcToken: String, serverURL: URL) async throws -> String {
        let client = Client.unauthenticated(serverURL: serverURL)

        let response = try await client.exchangeOIDCToken(
            body: .json(.init(token: oidcToken))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(tokenResponse):
                return tokenResponse.access_token
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ExchangeOIDCTokenServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ExchangeOIDCTokenServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ExchangeOIDCTokenServiceError.unknownError(statusCode)
        }
    }
}
