import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

public typealias CacheRun = Operations.getCacheRun.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetCacheRunServicing: Sendable {
    func getCacheRun(
        fullHandle: String,
        cacheRunId: String,
        serverURL: URL
    ) async throws -> CacheRun
}

enum GetCacheRunServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The cache run could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public struct GetCacheRunService: GetCacheRunServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func getCacheRun(
        fullHandle: String,
        cacheRunId: String,
        serverURL: URL
    ) async throws -> CacheRun {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getCacheRun(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    cache_run_id: cacheRunId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetCacheRunServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetCacheRunServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheRunServiceError.unknownError(statusCode)
        }
    }
}
