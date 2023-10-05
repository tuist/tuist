import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol DeleteProjectServicing {
    func deleteProject(
        projectId: Int,
        serverURL: URL
    ) async throws
}

enum DeleteProjectServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .unauthorized, .notFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The project could not be deleted due to an unknown cloud response of \(statusCode)."
        case let .unauthorized(message), let .notFound(message):
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
        let client = Client.cloud(serverURL: serverURL)

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
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteProjectServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw DeleteProjectServiceError.unknownError(statusCode)
        }
    }
}
