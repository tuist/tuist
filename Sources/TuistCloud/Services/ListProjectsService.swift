import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol ListProjectsServicing {
    func listProjects(
        serverURL: URL
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
        let client = Client(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [
                AuthenticationMiddleware(),
            ]
        )

        let response = try await client.listProjects(
            .init(
                query: .init()
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json.projects.map(CloudProject.init)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateProjectNextServiceError.unknownError(statusCode)
        }
    }
}
