import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListBuildIssuesServicing: Sendable {
    func listBuildIssues(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        type: String?,
        target: String?,
        stepType: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildIssues.Output.Ok.Body.jsonPayload
}

enum ListBuildIssuesServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the build issues due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct ListBuildIssuesService: ListBuildIssuesServicing {
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

    public func listBuildIssues(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        type: String?,
        target: String?,
        stepType: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildIssues.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listBuildIssues(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    build_id: buildId
                ),
                query: .init(
                    _type: type.flatMap { Operations.listBuildIssues.Input.Query._typePayload(rawValue: $0) },
                    target: target,
                    step_type: stepType,
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
                throw ListBuildIssuesServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListBuildIssuesServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBuildIssuesServiceError.unknownError(statusCode)
        }
    }
}
