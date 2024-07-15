import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol GetProjectServicing {
    func getProject(
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerProject
}

enum GetProjectServiceError: FatalError {
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
            return "We could not get the project due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class GetProjectService: GetProjectServicing {
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

    public func getProject(
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerProject {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.showProject(
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
            case let .json(project):
                return ServerProject(project)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetProjectServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetProjectServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetProjectServiceError.unknownError(statusCode)
        }
    }
}
