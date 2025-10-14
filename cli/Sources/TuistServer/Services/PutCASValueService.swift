import Foundation
import Mockable
import OpenAPIURLSession
import OpenAPIRuntime

@Mockable
public protocol PutKeyValueServicing: Sendable {
    func putKeyValue(
        casId: String,
        entries: [String: String],
        fullHandle: String,
        serverURL: URL
    ) async throws
}

public enum PutKeyValueServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case putValueFailed

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS value could not be stored due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        case .putValueFailed:
            return "The CAS value storage failed due to an unknown error."
        }
    }
}

public final class PutKeyValueService: PutKeyValueServicing {
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

    public func putKeyValue(
        casId: String,
        entries: [String: String],
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        
        let entriesPayload: Operations.putKeyValue.Input.Body.jsonPayload.entriesPayload = Operations.putKeyValue.Input.Body.jsonPayload.entriesPayload(
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
        case .ok:
            return
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw PutKeyValueServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw PutKeyValueServiceError.unauthorized(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw PutKeyValueServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw PutKeyValueServiceError.unknownError(statusCode)
        }
    }
}
