import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol DisconnectProjectRepositoryServicing {
    func disconnectProjectRepository(fullHandle: String, serverURL: URL) async throws
}

enum DisconnectProjectRepositoryServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not unlink the project from its repository due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct DisconnectProjectRepositoryService: DisconnectProjectRepositoryServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func disconnectProjectRepository(fullHandle: String, serverURL: URL) async throws {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).disconnectProjectRepository(
            .init(path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle))
        )
        switch response {
        case .noContent: return
        case let .forbidden(value): throw DisconnectProjectRepositoryServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw DisconnectProjectRepositoryServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw DisconnectProjectRepositoryServiceError.unknownError(statusCode)
        }
    }
}
