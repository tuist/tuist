import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol ListProjectsServicing {
    func listProjects(
        serverURL: URL
    ) async throws -> [CloudProject]

    func listProjects(
        serverURL: URL,
        accountName: String?,
        projectName: String?
    ) async throws -> [CloudProject]
}

enum ListProjectsServiceError: FatalError {
    case unknownError(Int)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The project could not be listed due to an unknown cloud response of \(statusCode)."
        }
    }
}

public final class ListProjectsService: ListProjectsServicing {
    public init() {}

    public func listProjects(
        serverURL: URL
    ) async throws -> [CloudProject] {
        try await listProjects(
            serverURL: serverURL,
            accountName: nil,
            projectName: nil
        )
    }

    public func listProjects(
        serverURL: URL,
        accountName: String?,
        projectName: String?
    ) async throws -> [CloudProject] {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.listProjects(
            .init(
                query: .init(
                    account_name: accountName,
                    project_name: projectName
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json.projects.map(CloudProject.init)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListProjectsServiceError.unknownError(statusCode)
        }
    }
}
