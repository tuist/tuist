import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ConnectProjectRepositoryServicing {
    func connectProjectRepository(
        fullHandle: String,
        repositoryFullHandle: String,
        serverURL: URL
    ) async throws -> String
}

enum ConnectProjectRepositoryServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case conflict(String)
    case unprocessableContent(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message), let .conflict(message),
             let .unprocessableContent(message):
            return message
        case let .unknownError(statusCode):
            return "We could not link the project to the repository due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct ConnectProjectRepositoryService: ConnectProjectRepositoryServicing {
    private let fullHandleService: FullHandleServicing

    public init() {
        self.init(fullHandleService: FullHandleService())
    }

    init(fullHandleService: FullHandleServicing) {
        self.fullHandleService = fullHandleService
    }

    public func connectProjectRepository(
        fullHandle: String,
        repositoryFullHandle: String,
        serverURL: URL
    ) async throws -> String {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.connectProjectRepository(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(.init(repository_full_handle: repositoryFullHandle))
            )
        )
        switch response {
        case let .ok(value): return try value.body.json.repository_full_handle
        case let .badRequest(value): throw ConnectProjectRepositoryServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw ConnectProjectRepositoryServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw ConnectProjectRepositoryServiceError.notFound(try value.body.json.message)
        case let .conflict(value): throw ConnectProjectRepositoryServiceError.conflict(try value.body.json.message)
        case let .unprocessableContent(value):
            throw ConnectProjectRepositoryServiceError.unprocessableContent(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw ConnectProjectRepositoryServiceError.unknownError(statusCode)
        }
    }
}
