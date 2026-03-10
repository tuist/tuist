import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

@Mockable
public protocol ListModuleCacheTargetsServicing: Sendable {
    func listModuleCacheTargets(
        fullHandle: String,
        serverURL: URL,
        runId: String,
        cacheStatus: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listModuleCacheTargets.Output.Ok.Body.jsonPayload
}

enum ListModuleCacheTargetsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the module cache targets due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message):
            return message
        }
    }
}

public struct ListModuleCacheTargetsService: ListModuleCacheTargetsServicing {
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

    public func listModuleCacheTargets(
        fullHandle: String,
        serverURL: URL,
        runId: String,
        cacheStatus: String?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listModuleCacheTargets.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listModuleCacheTargets(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    run_id: runId
                ),
                query: .init(
                    cache_status: cacheStatus.flatMap {
                        Operations.listModuleCacheTargets.Input.Query.cache_statusPayload(rawValue: $0)
                    },
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
                throw ListModuleCacheTargetsServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw ListModuleCacheTargetsServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListModuleCacheTargetsServiceError.unknownError(statusCode)
        }
    }
}
