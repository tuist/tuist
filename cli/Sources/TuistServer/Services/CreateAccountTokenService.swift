import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol CreateAccountTokenServicing {
    func createAccountToken(
        accountHandle: String,
        scopes: [AccountToken.Scope],
        serverURL: URL
    ) async throws -> String
}

enum CreateAccountTokenServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not create a new account token due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CreateAccountTokenService: CreateAccountTokenServicing {
    public init() {}

    public func createAccountToken(
        accountHandle: String,
        scopes: [AccountToken.Scope],
        serverURL: URL
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)

        let scopes: Operations.createAccountToken.Input.Body.jsonPayload.scopesPayload = scopes.map {
            switch $0 {
            case .accountRegistryRead:
                .registry_read
            }
        }

        let response = try await client.createAccountToken(
            .init(
                path: .init(
                    account_handle: accountHandle
                ),
                body: .json(.init(scopes: scopes))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(accountToken):
                return accountToken.token
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw CreateAccountTokenServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw CreateAccountTokenServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateAccountTokenServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateAccountTokenServiceError.unknownError(statusCode)
        }
    }
}
