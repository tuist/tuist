import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol DeleteProjectServicing {
    func deleteProject(
        projectId: Int,
        serverURL: URL
    ) async throws
}

enum DeleteProjectServiceError: FatalError {
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
            return "The project could not be deleted due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .unauthorized(message), let .notFound(message):
            return message
        }
    }
}

public final class DeleteProjectService: DeleteProjectServicing {
    public init() {}

    public func deleteProject(
        projectId: Int,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.deleteProject(
            .init(
                path: .init(id: projectId)
            )
        )
        switch response {
        case .noContent:
            // noop
            break
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw DeleteProjectServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw DeleteProjectServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw DeleteProjectServiceError.unknownError(statusCode)
        }
    }
}
