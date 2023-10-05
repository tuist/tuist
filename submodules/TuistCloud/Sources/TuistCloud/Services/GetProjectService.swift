import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol GetProjectServicing {
    func getProject(
        accountName: String,
        projectName: String,
        serverURL: URL
    ) async throws -> CloudProject
}

enum GetProjectServiceError: FatalError {
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
            return "We could not get the project due to an unknown cloud response of \(statusCode)."
        case let .unauthorized(message), let .notFound(message):
            return message
        }
    }
}

public final class GetProjectService: GetProjectServicing {
    public init() {}

    public func getProject(
        accountName: String,
        projectName: String,
        serverURL: URL
    ) async throws -> CloudProject {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.getProject(
            .init(
                path: .init(
                    account_name: accountName,
                    project_name: projectName
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
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetProjectServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetProjectServiceError.unknownError(statusCode)
        }
    }
}
