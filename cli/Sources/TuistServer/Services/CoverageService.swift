import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol CoverageServicing: Sendable {
    func getBranchCoverage(fullHandle: String, serverURL: URL, branch: String?) async throws
        -> Operations.getBranchCoverage.Output.Ok.Body.jsonPayload

    func getCommitCoverage(fullHandle: String, serverURL: URL, commitSHA: String) async throws
        -> Operations.getCommitCoverage.Output.Ok.Body.jsonPayload

    func listCoverageFiles(
        fullHandle: String,
        serverURL: URL,
        commitSHA: String,
        search: String?,
        sortBy: String?,
        sortOrder: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listCommitCoverageFiles.Output.Ok.Body.jsonPayload

    func getCoverageFile(
        fullHandle: String,
        serverURL: URL,
        commitSHA: String,
        path: String,
        includeLines: Bool
    ) async throws -> Operations.getCommitCoverageFile.Output.Ok.Body.jsonPayload
}

enum CoverageServiceError: LocalizedError, Equatable {
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not read the coverage due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct CoverageService: CoverageServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func getBranchCoverage(fullHandle: String, serverURL: URL, branch: String?) async throws
        -> Operations.getBranchCoverage.Output.Ok.Body.jsonPayload
    {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getBranchCoverage(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                query: .init(branch: branch)
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .unauthorized(value): throw CoverageServiceError.unauthorized(try value.body.json.message)
        case let .forbidden(value): throw CoverageServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw CoverageServiceError.notFound(try value.body.json.message)
        case let .undocumented(statusCode, _): throw CoverageServiceError.unknownError(statusCode)
        }
    }

    public func getCommitCoverage(fullHandle: String, serverURL: URL, commitSHA: String) async throws
        -> Operations.getCommitCoverage.Output.Ok.Body.jsonPayload
    {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getCommitCoverage(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    git_commit_sha: commitSHA
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .unauthorized(value): throw CoverageServiceError.unauthorized(try value.body.json.message)
        case let .forbidden(value): throw CoverageServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw CoverageServiceError.notFound(try value.body.json.message)
        case let .undocumented(statusCode, _): throw CoverageServiceError.unknownError(statusCode)
        }
    }

    public func listCoverageFiles(
        fullHandle: String,
        serverURL: URL,
        commitSHA: String,
        search: String?,
        sortBy: String?,
        sortOrder: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listCommitCoverageFiles.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listCommitCoverageFiles(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    git_commit_sha: commitSHA
                ),
                query: .init(
                    page: page,
                    page_size: pageSize,
                    search: search,
                    sort_by: sortBy.flatMap { Operations.listCommitCoverageFiles.Input.Query.sort_byPayload(rawValue: $0) },
                    sort_order: sortOrder
                        .flatMap { Operations.listCommitCoverageFiles.Input.Query.sort_orderPayload(rawValue: $0) }
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .unauthorized(value): throw CoverageServiceError.unauthorized(try value.body.json.message)
        case let .forbidden(value): throw CoverageServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw CoverageServiceError.notFound(try value.body.json.message)
        case let .undocumented(statusCode, _): throw CoverageServiceError.unknownError(statusCode)
        }
    }

    public func getCoverageFile(
        fullHandle: String,
        serverURL: URL,
        commitSHA: String,
        path: String,
        includeLines: Bool
    ) async throws -> Operations.getCommitCoverageFile.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).getCommitCoverageFile(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    git_commit_sha: commitSHA
                ),
                query: .init(path: path, include_lines: includeLines)
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .unauthorized(value): throw CoverageServiceError.unauthorized(try value.body.json.message)
        case let .forbidden(value): throw CoverageServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw CoverageServiceError.notFound(try value.body.json.message)
        case let .undocumented(statusCode, _): throw CoverageServiceError.unknownError(statusCode)
        }
    }
}
