import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol BazelInvocationsServicing: Sendable {
    func listBazelInvocations(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listBazelInvocations.Output.Ok.Body.jsonPayload

    func getBazelInvocation(fullHandle: String, serverURL: URL, invocationId: String) async throws
        -> Operations.getBazelInvocation.Output.Ok.Body.jsonPayload

    func listBazelBuildSteps(
        fullHandle: String,
        serverURL: URL,
        invocationId: String,
        status: String?,
        target: String?,
        search: String?,
        sortBy: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listBazelBuildSteps.Output.Ok.Body.jsonPayload

    func getBazelBuildStep(fullHandle: String, serverURL: URL, invocationId: String, stepId: String) async throws
        -> Operations.getBazelBuildStep.Output.Ok.Body.jsonPayload

    func listBazelInvocationLogs(
        fullHandle: String,
        serverURL: URL,
        invocationId: String,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listBazelInvocationLogs.Output.Ok.Body.jsonPayload
}

enum BazelInvocationsServiceError: LocalizedError, Equatable {
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .badRequest(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not read the Bazel invocations due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct BazelInvocationsService: BazelInvocationsServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listBazelInvocations(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listBazelInvocations.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listBazelInvocations(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                query: .init(
                    page_size: pageSize,
                    page: page,
                    status: status.flatMap { Operations.listBazelInvocations.Input.Query.statusPayload(rawValue: $0) },
                    git_branch: gitBranch
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw BazelInvocationsServiceError.forbidden(try value.body.json.message)
        case let .undocumented(statusCode, _): throw BazelInvocationsServiceError.unknownError(statusCode)
        }
    }

    public func getBazelInvocation(fullHandle: String, serverURL: URL, invocationId: String) async throws
        -> Operations.getBazelInvocation.Output.Ok.Body.jsonPayload
    {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getBazelInvocation(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    invocation_id: invocationId
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw BazelInvocationsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw BazelInvocationsServiceError.notFound(try value.body.json.message)
        case let .undocumented(statusCode, _): throw BazelInvocationsServiceError.unknownError(statusCode)
        }
    }

    public func listBazelBuildSteps(
        fullHandle: String,
        serverURL: URL,
        invocationId: String,
        status: String?,
        target: String?,
        search: String?,
        sortBy: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listBazelBuildSteps.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listBazelBuildSteps(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    invocation_id: invocationId
                ),
                query: .init(
                    page: page,
                    page_size: pageSize,
                    search: search,
                    target: target,
                    status: status.flatMap { Operations.listBazelBuildSteps.Input.Query.statusPayload(rawValue: $0) },
                    sort_by: sortBy.flatMap { Operations.listBazelBuildSteps.Input.Query.sort_byPayload(rawValue: $0) }
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw BazelInvocationsServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw BazelInvocationsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw BazelInvocationsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw BazelInvocationsServiceError.unknownError(statusCode)
        }
    }

    public func getBazelBuildStep(fullHandle: String, serverURL: URL, invocationId: String, stepId: String) async throws
        -> Operations.getBazelBuildStep.Output.Ok.Body.jsonPayload
    {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getBazelBuildStep(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    invocation_id: invocationId,
                    step_id: stepId
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw BazelInvocationsServiceError.badRequest(try value.body.json.message)
        case let .forbidden(value): throw BazelInvocationsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw BazelInvocationsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw BazelInvocationsServiceError.unknownError(statusCode)
        }
    }

    public func listBazelInvocationLogs(
        fullHandle: String,
        serverURL: URL,
        invocationId: String,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listBazelInvocationLogs.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listBazelInvocationLogs(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    invocation_id: invocationId
                ),
                query: .init(page_size: pageSize, page: page)
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw BazelInvocationsServiceError.forbidden(try value.body.json.message)
        case let .undocumented(statusCode, _): throw BazelInvocationsServiceError.unknownError(statusCode)
        }
    }
}
