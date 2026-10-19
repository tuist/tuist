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
    private let fullHandleService: FullHandleServicing

    public init() {
        self.init(fullHandleService: FullHandleService())
    }

    init(fullHandleService: FullHandleServicing) {
        self.fullHandleService = fullHandleService
    }

    public func disconnectProjectRepository(fullHandle: String, serverURL: URL) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.disconnectProjectRepository(
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
