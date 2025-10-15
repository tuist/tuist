import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession

@Mockable
public protocol GetCacheValueServicing: Sendable {
    func getCacheValue(
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Operations.getCacheValue.Output.Ok.Body.jsonPayload?
}

public enum GetCacheValueServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS value could not be retrieved due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message):
            return message
        }
    }
}

public final class GetCacheValueService: GetCacheValueServicing {
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

    public func getCacheValue(
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Operations.getCacheValue.Output.Ok.Body.jsonPayload? {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getCacheValue(
            Operations.getCacheValue.Input(
                path: .init(
                    cas_id: casId
                ),
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                )
            )
        )

        switch response {
        case let .ok(success):
            switch success.body {
            case let .json(jsonPayload):
                return jsonPayload
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetCacheValueServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetCacheValueServiceError.unauthorized(error.message)
            }
        case .notFound:
            return nil
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheValueServiceError.unknownError(statusCode)
        }
    }
}
