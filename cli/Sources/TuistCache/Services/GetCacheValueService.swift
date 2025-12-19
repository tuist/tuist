import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

/// Type alias for the generated KeyValueResponse schema
public typealias KeyValueResponse = Components.Schemas.KeyValueResponse

/// Type alias for a single key-value entry
public typealias KeyValueEntry = Components.Schemas.KeyValueResponse.entriesPayloadPayload

@Mockable
public protocol GetCacheValueServicing: Sendable {
    func getCacheValue(
        casId: String,
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> KeyValueResponse?
}

public enum GetCacheValueServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS value could not be retrieved due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .badRequest(message):
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
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> KeyValueResponse? {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getKeyValue(
            Operations.getKeyValue.Input(
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
            case let .json(keyValueResponse):
                return keyValueResponse
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetCacheValueServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw GetCacheValueServiceError.badRequest(error.message)
            }
        case .notFound:
            return nil
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheValueServiceError.unknownError(statusCode)
        }
    }
}
