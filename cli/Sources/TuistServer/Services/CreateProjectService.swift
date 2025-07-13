import Foundation
import Mockable
import OpenAPIURLSession

@Mockable
public protocol CreateProjectServicing {
    func createProject(
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerProject
}

enum CreateProjectServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case badRequest(String)
    case unauthorized(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The project could not be created due to an unknown Cloud response of \(statusCode)."
        case let .forbidden(message), let .badRequest(message), let .unauthorized(message):
            return message
        }
    }
}

public final class CreateProjectService: CreateProjectServicing {
    public init() {}

    public func createProject(
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerProject {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.createProject(
            .init(
                body: .json(
                    .init(
                        full_handle: fullHandle
                    )
                )
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(project):
                return ServerProject(project)
            }
        case let .forbidden(forbiddenResponse):
            switch forbiddenResponse.body {
            case let .json(error):
                throw CreateProjectServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CreateProjectServiceError.unknownError(statusCode)
        case let .badRequest(badRequestResponse):
            switch badRequestResponse.body {
            case let .json(error):
                throw CreateProjectServiceError.badRequest(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CreateProjectServiceError.unauthorized(error.message)
            }
        }
    }
}
