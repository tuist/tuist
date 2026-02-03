import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListBuildsServicing: Sendable {
    func listBuilds(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        configuration: String?,
        tags: [String]?,
        values: [String]?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuilds.Output.Ok.Body.jsonPayload
}

enum ListBuildsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the builds due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

public struct ListBuildsService: ListBuildsServicing {
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

    public func listBuilds(
        fullHandle: String,
        serverURL: URL,
        gitBranch: String?,
        status: String?,
        scheme: String?,
        configuration: String?,
        tags: [String]?,
        values: [String]?,
        page: Int?,
        pageSize: Int
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
                    status: status.flatMap { Operations.listBuilds.Input.Query.statusPayload(rawValue: $0) },
                    category: nil,
                    scheme: scheme,
                    configuration: configuration,
                    git_branch: gitBranch,
                    tags: tags,
                    values: values,
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
