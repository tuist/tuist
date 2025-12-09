import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol ListAccountTokensServicing {
    func listAccountTokens(
        accountHandle: String,
        serverURL: URL
    ) async throws -> [Operations.listAccountTokens.Output.Ok.Body.jsonPayload.tokensPayloadPayload]
}

enum ListAccountTokensServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the account tokens due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class ListAccountTokensService: ListAccountTokensServicing {
    public init() {}

    public func listAccountTokens(
        accountHandle: String,
        serverURL: URL
    ) async throws -> [Operations.listAccountTokens.Output.Ok.Body.jsonPayload.tokensPayloadPayload] {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.listAccountTokens(
            .init(
                path: .init(account_handle: accountHandle)
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(response):
                return response.tokens
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListAccountTokensServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListAccountTokensServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListAccountTokensServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListAccountTokensServiceError.unknownError(statusCode)
        }
    }
}
