import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol CargoBuildsServicing: Sendable {
    func listCargoBuilds(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        command: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listCargoBuilds.Output.Ok.Body.jsonPayload

    func getCargoBuild(fullHandle: String, serverURL: URL, buildId: String) async throws
        -> Operations.getCargoBuild.Output.Ok.Body.jsonPayload
}

enum CargoBuildsServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not read the Cargo builds due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct CargoBuildsService: CargoBuildsServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listCargoBuilds(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        command: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listCargoBuilds.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listCargoBuilds(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                query: .init(
                    git_branch: gitBranch,
                    status: status.flatMap { Operations.listCargoBuilds.Input.Query.statusPayload(rawValue: $0) },
                    command: command,
                    page_size: pageSize,
                    page: page
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw CargoBuildsServiceError.forbidden(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw CargoBuildsServiceError.unknownError(statusCode)
        }
    }

    public func getCargoBuild(fullHandle: String, serverURL: URL, buildId: String) async throws
        -> Operations.getCargoBuild.Output.Ok.Body.jsonPayload
    {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getCargoBuild(
            .init(path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle, build_id: buildId))
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw CargoBuildsServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw CargoBuildsServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw CargoBuildsServiceError.unknownError(statusCode)
        }
    }
}
