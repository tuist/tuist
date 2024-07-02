import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol GetProjectServicing {
    func getProject(
        fullHandle: String,
        serverURL: URL
    ) async throws -> CloudProject
}

enum GetProjectServiceError: FatalError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case invalidHandle(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .notFound, .unauthorized, .invalidHandle:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the project due to an unknown cloud response of \(statusCode)."
        case let .invalidHandle(fullHandle):
            return "The project full handle \(fullHandle) is not in the format of account-handle/project-handle."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class GetProjectService: GetProjectServicing {
    public init() {}

    public func getProject(
        fullHandle: String,
        serverURL: URL
    ) async throws -> CloudProject {
        let client = Client.cloud(serverURL: serverURL)
        let components = fullHandle.components(separatedBy: "/")
        guard components.count == 2
        else {
            throw GetProjectServiceError.invalidHandle(fullHandle)
        }

        let accountHandle = components[0]
        let projectHandle = components[1]

        let response = try await client.showProject(
            .init(
                path: .init(
                    account_name: accountHandle,
                    project_name: projectHandle
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(project):
                return CloudProject(project)
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
