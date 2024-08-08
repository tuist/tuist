import Foundation
import Mockable
import OpenAPIURLSession
import TuistSupport

@Mockable
public protocol UpdateProjectServicing {
    func updateProject(
        fullHandle: String,
        serverURL: URL,
        defaultBranch: String?
    ) async throws -> ServerProject
}

enum UpdateProjectServiceError: FatalError {
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
            return "We could not update the project due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        }
    }
}

public final class UpdateProjectService: UpdateProjectServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func updateProject(
        fullHandle: String,
        serverURL: URL,
        defaultBranch: String?
    ) async throws -> ServerProject {
        let client = Client.authenticated(serverURL: serverURL)

        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.updateProject(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(
                    .init(
                        default_branch: defaultBranch
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
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UpdateProjectServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UpdateProjectServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UpdateProjectServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UpdateProjectServiceError.unknownError(statusCode)
        }
    }
}
