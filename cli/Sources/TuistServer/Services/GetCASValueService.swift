import Foundation
import Mockable
import OpenAPIURLSession
import OpenAPIRuntime

@Mockable
public protocol GetKeyValueServicing: Sendable {
    func getKeyValue(
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Operations.getKeyValue.Output.Ok.Body.jsonPayload?
}

public enum GetKeyValueServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case getValueFailed

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS value could not be retrieved due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message):
            return message
        case .getValueFailed:
            return "The CAS value retrieval failed due to an unknown error."
        }
    }
}

public final class GetKeyValueService: GetKeyValueServicing {
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

    public func getKeyValue(
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Operations.getKeyValue.Output.Ok.Body.jsonPayload? {
        let client = Client.authenticated(serverURL: serverURL)
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
            guard case let .json(json) = success.body else {
                throw GetKeyValueServiceError.getValueFailed
            }
            
            return json
            
        case .notFound:
            return nil
        case let .undocumented(statusCode: statusCode, _):
            throw GetKeyValueServiceError.unknownError(statusCode)
        }
    }
}
