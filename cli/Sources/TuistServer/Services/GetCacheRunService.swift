import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol GetCacheRunServicing {
    func getCacheRun(
        fullHandle: String,
        runId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.Run
}

enum GetCacheRunServiceError: LocalizedError {
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        case let .unauthorized(message):
            return message
        case let .unknownError(statusCode):
            return "The cache run could not be retrieved due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public final class GetCacheRunService: GetCacheRunServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(fullHandleService: FullHandleServicing) {
        self.fullHandleService = fullHandleService
    }

    public func getCacheRun(
        fullHandle: String,
        runId: String,
        serverURL: URL
    ) async throws -> Components.Schemas.Run {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getCacheRun(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    run_id: runId
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
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetCacheRunServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheRunServiceError.unknownError(statusCode)
        }
    }
}
