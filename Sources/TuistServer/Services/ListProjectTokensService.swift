import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol ListProjectTokensServicing {
    func listProjectTokens(
        fullHandle: String,
        serverURL: URL
    ) async throws -> [ServerProjectToken]
}

enum ListProjectTokensServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .notFound, .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the project tokens due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class ListProjectTokensService: ListProjectTokensServicing {
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

    public func listProjectTokens(
        fullHandle: String,
        serverURL: URL
    ) async throws -> [ServerProjectToken] {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listProjectTokens(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(response):
                return response.tokens.map(ServerProjectToken.init)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListProjectTokensServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListProjectTokensServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListProjectTokensServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListProjectTokensServiceError.unknownError(statusCode)
        }
    }
}
