import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol CreateProjectTokenServicing {
    func createProjectToken(
        fullHandle: String,
        serverURL: URL
    ) async throws -> String
}

enum CreateProjectTokenServiceError: FatalError {
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
            return "We could not create a new project token due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CreateProjectTokenService: CreateProjectTokenServicing {
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

    public func createProjectToken(
        fullHandle: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.createProjectToken(
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
            case let .json(projectToken):
                return projectToken.token
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw CreateProjectTokenServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw CreateProjectTokenServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateProjectTokenServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateProjectTokenServiceError.unknownError(statusCode)
        }
    }
}
