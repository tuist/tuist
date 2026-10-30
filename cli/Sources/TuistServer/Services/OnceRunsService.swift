import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol OnceRunsServicing: Sendable {
    func listOnceRuns(
        fullHandle: String,
        serverURL: URL,
        kind: String?,
        status: String?,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listOnceRuns.Output.Ok.Body.jsonPayload

    func getOnceRun(fullHandle: String, serverURL: URL, runId: String) async throws -> Operations.getOnceRun.Output.Ok.Body
        .jsonPayload
}

enum OnceRunsServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not read the Once runs due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct OnceRunsService: OnceRunsServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listOnceRuns(
        fullHandle: String,
        serverURL: URL,
        kind: String?,
        status: String?,
        gitBranch: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listOnceRuns.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listOnceRuns(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                query: .init(
                    kind: kind.flatMap { Operations.listOnceRuns.Input.Query.kindPayload(rawValue: $0) },
                    status: status.flatMap { Operations.listOnceRuns.Input.Query.statusPayload(rawValue: $0) },
                    git_branch: gitBranch,
                    page_size: pageSize,
                    page: page
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw OnceRunsServiceError.forbidden(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw OnceRunsServiceError.unknownError(statusCode)
        }
    }

    public func getOnceRun(fullHandle: String, serverURL: URL, runId: String) async throws -> Operations.getOnceRun.Output.Ok.Body
        .jsonPayload
    {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getOnceRun(
            .init(path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle, once_run_id: runId))
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw OnceRunsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw OnceRunsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw OnceRunsServiceError.unknownError(statusCode)
        }
    }
}
