import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol CreateAccountTokenServicing {
    func createAccountToken(
        accountHandle: String,
        scopes: [Components.Schemas.CreateAccountToken.scopesPayloadPayload],
        name: String,
        expiresAt: Date?,
        projectHandles: [String]?,
        serverURL: URL
    ) async throws -> Operations.createAccountToken.Output.Ok.Body.jsonPayload
}

enum CreateAccountTokenServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case badRequest(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not create a new account token due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message), let .badRequest(message):
            return message
        }
    }
}

public final class CreateAccountTokenService: CreateAccountTokenServicing {
    public init() {}

    public func createAccountToken(
        accountHandle: String,
        scopes: [Components.Schemas.CreateAccountToken.scopesPayloadPayload],
        name: String,
        expiresAt: Date?,
        projectHandles: [String]?,
        serverURL: URL
    ) async throws -> Operations.createAccountToken.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)

        let operationScopes = scopes.compactMap {
            Operations.createAccountToken.Input.Body.jsonPayload.scopesPayloadPayload(rawValue: $0.rawValue)
        }

        let response = try await client.createAccountToken(
            .init(
                path: .init(account_handle: accountHandle),
                body: .json(.init(
                    expires_at: expiresAt,
                    name: name,
                    project_handles: projectHandles,
                    scopes: operationScopes
                ))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(accountToken):
                return accountToken
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
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw CreateAccountTokenServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateAccountTokenServiceError.unknownError(statusCode)
        }
    }
}
