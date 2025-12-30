import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol RevokeAccountTokenServicing {
    func revokeAccountToken(
        accountHandle: String,
        tokenName: String,
        serverURL: URL
    ) async throws
}

enum RevokeAccountTokenServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not revoke the account token due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class RevokeAccountTokenService: RevokeAccountTokenServicing {
    public init() {}

    public func revokeAccountToken(
        accountHandle: String,
        tokenName: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.revokeAccountToken(
            .init(
                path: .init(
                    account_handle: accountHandle,
                    token_name: tokenName
                )
            )
        )
        switch response {
        case .noContent:
            break
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw RevokeAccountTokenServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw RevokeAccountTokenServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw RevokeAccountTokenServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw RevokeAccountTokenServiceError.unknownError(statusCode)
        }
    }
}
