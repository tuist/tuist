import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol RevokeProjectTokenServicing {
    func revokeProjectToken(
        projectTokenId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws
}

enum RevokeProjectTokenServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case badRequest(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .notFound, .unauthorized, .badRequest:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not revoke the project token due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message), let .badRequest(message):
            return message
        }
    }
}

public final class RevokeProjectTokenService: RevokeProjectTokenServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func revokeProjectToken(
        projectTokenId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.revokeProjectToken(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    id: projectTokenId
                )
            )
        )
        switch response {
        case .noContent:
            // noop
            break
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw RevokeProjectTokenServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw RevokeProjectTokenServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw RevokeProjectTokenServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw RevokeProjectTokenServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw RevokeProjectTokenServiceError.unknownError(statusCode)
        }
    }
}
