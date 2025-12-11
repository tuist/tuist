import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol PutCacheValueServicing: Sendable {
    func putCacheValue(
        casId: String,
        entries: [String: String],
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum PutCacheValueServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case badRequest(String)
    case putValueFailed

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS value could not be stored due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message), let .badRequest(message):
            return message
        case .putValueFailed:
            return "The CAS value storage failed due to an unknown error."
        }
    }
}

public final class PutCacheValueService: PutCacheValueServicing {
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

    public func putCacheValue(
        casId: String,
        entries: [String: String],
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )
        let handles = try fullHandleService.parse(fullHandle)

        let entriesPayload = Operations.putKeyValue.Input.Body.jsonPayload.entriesPayload(
            entries
                .filter { $0.key == "value" }
                .map {
                    Operations.putKeyValue.Input.Body.jsonPayload.entriesPayloadPayload(value: $0.value)
                }
        )

        let requestBody = Operations.putKeyValue.Input.Body.jsonPayload(
            cas_id: casId,
            entries: entriesPayload
        )

        let response = try await client.putKeyValue(
            .init(
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .json(requestBody)
            )
        )

        switch response {
        case .noContent:
            return
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw PutCacheValueServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw PutCacheValueServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw PutCacheValueServiceError.unknownError(statusCode)
        }
    }
}
