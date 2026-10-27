import Foundation
import Mockable
import OpenAPIRuntime
import TuistEnvironment

@Mockable
public protocol ExchangeOIDCTokenServicing: Sendable {
    func exchangeOIDCToken(oidcToken: String, serverURL: URL) async throws -> String
}

enum ExchangeOIDCTokenServiceError: LocalizedError {
    case unknownError(Int)
    case badRequest(String)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            "OIDC token exchange failed with status \(statusCode)."
        case let .badRequest(message):
            message
        case let .unauthorized(message):
            message
        case let .forbidden(message):
            message
        }
    }
}

public struct ExchangeOIDCTokenService: ExchangeOIDCTokenServicing {
    private let makeClient: (URL) -> Client

    public init() {
        makeClient = { Client.unauthenticated(serverURL: $0) }
    }

    init(makeClient: @escaping (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func exchangeOIDCToken(oidcToken: String, serverURL: URL) async throws -> String {
        let client = makeClient(serverURL)

        let accountHandle = Environment.current.variables["TUIST_OIDC_ACCOUNT"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let response = try await client.exchangeOIDCToken(
            body: .json(.init(account_handle: accountHandle, token: oidcToken))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(tokenResponse):
                return tokenResponse.access_token
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw ExchangeOIDCTokenServiceError.badRequest(error.message)
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
