import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListBuildCacheTasksServicing: Sendable {
    func listBuildCacheTasks(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        status: String?,
        type: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildCacheTasks.Output.Ok.Body.jsonPayload
}

enum ListBuildCacheTasksServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the build cache tasks due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct ListBuildCacheTasksService: ListBuildCacheTasksServicing {
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

    public func listBuildCacheTasks(
        fullHandle: String,
        serverURL: URL,
        buildId: String,
        status: String?,
        type: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listBuildCacheTasks.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listBuildCacheTasks(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    build_id: buildId
                ),
                query: .init(
                    status: status.flatMap { Operations.listBuildCacheTasks.Input.Query.statusPayload(rawValue: $0) },
                    _type: type.flatMap { Operations.listBuildCacheTasks.Input.Query._typePayload(rawValue: $0) },
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
                throw ListBuildCacheTasksServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListBuildCacheTasksServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListBuildCacheTasksServiceError.unknownError(statusCode)
        }
    }
}
