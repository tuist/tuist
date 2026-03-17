import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListTestRunsServicing: Sendable {
    func listTestRuns(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestRuns.Output.Ok.Body.jsonPayload
}

enum ListTestRunsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the test runs due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

public struct ListTestRunsService: ListTestRunsServicing {
    private let fullHandleService: FullHandleServicing

    public init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func listTestRuns(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestRuns.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestRuns(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    git_branch: gitBranch,
                    status: status.flatMap { Operations.listTestRuns.Input.Query.statusPayload(rawValue: $0) },
                    scheme: scheme,
                    page: page,
                    page_size: pageSize
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListTestRunsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestRunsServiceError.unknownError(statusCode)
        }
    }
}
