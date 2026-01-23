import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListGenerationsServicing: Sendable {
    func listGenerations(
        fullHandle: String,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listGenerations.Output.Ok.Body.jsonPayload
}

enum ListGenerationsServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The generations could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public final class ListGenerationsService: ListGenerationsServicing {
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

    public func listGenerations(
        fullHandle: String,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listGenerations.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listGenerations(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    git_ref: gitRef,
                    git_branch: gitBranch,
                    git_commit_sha: gitCommitSHA,
                    page_size: pageSize,
                    page: page
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListGenerationsServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListGenerationsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListGenerationsServiceError.unknownError(statusCode)
        }
    }
}
