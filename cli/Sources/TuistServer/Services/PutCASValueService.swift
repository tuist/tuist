import Foundation
import Mockable
import OpenAPIURLSession
import OpenAPIRuntime

@Mockable
public protocol PutCASValueServicing {
    func putCASValue(
        casId: String,
        entries: [String: String],
        fullHandle: String,
        serverURL: URL
    ) async throws
}

enum PutCASValueServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case putValueFailed

    var errorDescription: String? {
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

public final class PutCASValueService: PutCASValueServicing {
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

    public func putCASValue(
        casId: String,
        entries: [String: String],
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        
        let entriesPayload = Operations.putCASValue.Input.Body.jsonPayload.entriesPayload(
            // TODO: should probably change this for now to assume the key is always value 'cause this is probably causing issues
            additionalProperties: entries
        )
        
        let requestBody = Operations.putCASValue.Input.Body.jsonPayload(
            cas_id: casId,
            entries: entriesPayload
        )
        
        let response = try await client.putCASValue(
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
                throw PutCASValueServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw PutCASValueServiceError.unauthorized(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw PutCASValueServiceError.notFound(error.message)
            }
        case let .undocumented(statusCode: statusCode, _payload):
            throw PutCASValueServiceError.unknownError(statusCode)
        }
    }
}
