import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListBuildsServicing: Sendable {
    func listBuilds(
        fullHandle: String,
        status: String?,
        category: String?,
        scheme: String?,
        configuration: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listBuilds.Output.Ok.Body.jsonPayload
}

enum ListBuildsServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The builds could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public final class ListBuildsService: ListBuildsServicing {
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

    public func listBuilds(
        fullHandle: String,
        status: String?,
        category: String?,
        scheme: String?,
        configuration: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listBuilds.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listBuilds(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    status: status,
                    category: category,
                    scheme: scheme,
                    configuration: configuration,
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
                throw ListBuildsServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListBuildsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBuildsServiceError.unknownError(statusCode)
        }
    }
}
