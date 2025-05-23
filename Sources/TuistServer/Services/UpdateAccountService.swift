import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol UpdateAccountServicing {
    func updateAccount(
        serverURL: URL,
        accountHandle: String,
        handle: String?
    ) async throws -> ServerAccount
}

enum UpdateAccountServiceError: LocalizedError {
    case unknownError(Int)
    case badRequest(String)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not update the account due to an unknown Tuist response of \(statusCode)."
        case let .badRequest(message), let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public final class UpdateAccountService: UpdateAccountServicing {
    public init() {}

    public func updateAccount(
        serverURL: URL,
        accountHandle: String,
        handle: String?
    ) async throws -> ServerAccount {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.updateAccount(
            .init(
                path: .init(
                    account_handle: accountHandle
                ),
                body: .json(
                    .init(
                        handle: handle
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(account):
                return ServerAccount(account)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UpdateAccountServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UpdateAccountServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw UpdateAccountServiceError.badRequest(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UpdateAccountServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateAccountServiceError.unknownError(statusCode)
        }
    }
}
