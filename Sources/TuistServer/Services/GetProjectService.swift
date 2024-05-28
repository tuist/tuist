import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
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
    case forbidden(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .forbidden, .notFound:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "We could not get the project due to an unknown cloud response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
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

        let response = try await client.showProject(
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
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetProjectServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetProjectServiceError.unknownError(statusCode)
        }
    }
}
