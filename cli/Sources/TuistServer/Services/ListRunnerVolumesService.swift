import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public typealias RunnerVolumesPage = Operations.listRunnerVolumes.Output.Ok.Body.jsonPayload

@Mockable
public protocol ListRunnerVolumesServicing {
    func listRunnerVolumes(
        accountHandle: String,
        serverURL: URL,
        name: String?,
        repository: String?,
        sortBy: String?,
        sortOrder: String?,
        page: Int,
        pageSize: Int
    ) async throws -> RunnerVolumesPage
}

enum ListRunnerVolumesServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not list runner volumes due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct ListRunnerVolumesService: ListRunnerVolumesServicing {
    public init() {}

    public func listRunnerVolumes(
        accountHandle: String,
        serverURL: URL,
        name: String?,
        repository: String?,
        sortBy: String?,
        sortOrder: String?,
        page: Int,
        pageSize: Int
    ) async throws -> RunnerVolumesPage {
        let client = Client.authenticated(serverURL: serverURL)
        let response = try await client.listRunnerVolumes(.init(
            path: .init(account_handle: accountHandle),
            query: .init(
                name: name,
                page: page,
                page_size: pageSize,
                repository: repository,
                sort_by: sortBy.flatMap { .init(rawValue: $0) },
                sort_order: sortOrder.flatMap { .init(rawValue: $0) }
            )
        ))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw ListRunnerVolumesServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw ListRunnerVolumesServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw ListRunnerVolumesServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw ListRunnerVolumesServiceError.unknownError(statusCode)
        }
    }
}
