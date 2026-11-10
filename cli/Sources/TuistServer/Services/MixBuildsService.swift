import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol MixBuildsServicing: Sendable {
    func listMixBuilds(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        mixEnv: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listMixBuilds.Output.Ok.Body.jsonPayload

    func getMixBuild(fullHandle: String, serverURL: URL, buildId: String) async throws
        -> Operations.getMixBuild.Output.Ok.Body.jsonPayload
}

enum MixBuildsServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not read the Mix builds due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct MixBuildsService: MixBuildsServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listMixBuilds(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        mixEnv: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listMixBuilds.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listMixBuilds(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                query: .init(
                    git_branch: gitBranch,
                    status: status.flatMap { Operations.listMixBuilds.Input.Query.statusPayload(rawValue: $0) },
                    mix_env: mixEnv,
                    page_size: pageSize,
                    page: page
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw MixBuildsServiceError.forbidden(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw MixBuildsServiceError.unknownError(statusCode)
        }
    }

    public func getMixBuild(fullHandle: String, serverURL: URL, buildId: String) async throws
        -> Operations.getMixBuild.Output.Ok.Body.jsonPayload
    {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getMixBuild(
            .init(path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle, build_id: buildId))
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw MixBuildsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw MixBuildsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw MixBuildsServiceError.unknownError(statusCode)
        }
    }
}
