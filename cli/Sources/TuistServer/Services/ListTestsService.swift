import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListTestsServicing: Sendable {
    func listTests(
        fullHandle: String,
        status: String?,
        scheme: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listTests.Output.Ok.Body.jsonPayload
}

enum ListTestsServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The tests could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public final class ListTestsService: ListTestsServicing {
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

    public func listTests(
        fullHandle: String,
        status: String?,
        scheme: String?,
        gitBranch: String?,
        gitCommitSHA: String?,
        gitRef: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listTests.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTests(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    status: status,
                    scheme: scheme,
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
                throw ListTestsServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListTestsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestsServiceError.unknownError(statusCode)
        }
    }
}
