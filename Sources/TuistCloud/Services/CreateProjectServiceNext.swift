import Foundation
import OpenAPIURLSession
import TuistSupport

public protocol CreateProjectNextServicing {
    func createProject(
        name: String,
        organization: String?,
        serverURL: URL
    ) async throws -> CloudProject
}

enum CreateProjectNextServiceError: FatalError {
    case unknownError(Int)
    case badRequest(String)

    var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .badRequest:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The project could not be created due to an unknown cloud response of \(statusCode)."
        case let .badRequest(message):
            return message
        }
    }
}

public final class CreateProjectNextService: CreateProjectNextServicing {
    public init() {}

    public func createProject(
        name: String,
        organization: String?,
        serverURL: URL
    ) async throws -> CloudProject {
        let client = Client.cloud(serverURL: serverURL)

        let response = try await client.createProject(
            .init(
                query: .init(
                    name: name,
                    organization: organization
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(project):
                return CloudProject(project)
            }
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateProjectNextServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateProjectNextServiceError.unknownError(statusCode)
        }
    }
}
