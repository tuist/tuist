import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol ListProjectsServicing {
    func listProjects(
        serverURL: URL
    ) async throws -> [ServerProject]

    func listProjects(
        serverURL: URL,
        accountName: String?,
        projectName: String?
    ) async throws -> [ServerProject]
}

enum ListProjectsServiceError: FatalError {
    case unknownError(Int)
    case unauthorized(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .unauthorized:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The project could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        }
    }
}

public final class ListProjectsService: ListProjectsServicing {
    public init() {}

    public func listProjects(
        serverURL: URL
    ) async throws -> [ServerProject] {
        try await listProjects(
            serverURL: serverURL,
            accountName: nil,
            projectName: nil
        )
    }

    public func listProjects(
        serverURL: URL,
        accountName _: String?,
        projectName _: String?
    ) async throws -> [ServerProject] {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.listProjects(
            .init()
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json.projects.map(ServerProject.init)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListProjectsServiceError.unknownError(statusCode)
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DeleteOrganizationServiceError.unauthorized(error.message)
            }
        }
    }
}
