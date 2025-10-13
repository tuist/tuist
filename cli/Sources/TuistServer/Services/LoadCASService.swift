import Foundation
import Mockable
import OpenAPIURLSession
import OpenAPIRuntime

@Mockable
public protocol LoadCASServicing {
    func loadCAS(
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Data
}

enum LoadCASServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case loadFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS artifact could not be loaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        case .loadFailed:
            return "The CAS artifact load failed due to an unknown error."
        case .invalidResponse:
            return "The server returned an invalid response format."
        }
    }
}

public final class LoadCASService: LoadCASServicing {
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

    public func loadCAS(
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws -> Data {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        
        let response = try await client.getCASArtifact(
            .init(
                path: .init(id: casId),
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                )
            )
        )
        
        switch response {
        case let .ok(success):
            guard case let .binary(httpBody) = success.body else {
                throw LoadCASServiceError.invalidResponse
            }
            
            // Convert HTTPBody to Data
            let data = try await Data(collecting: httpBody, upTo: .max)
            return data
            
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw LoadCASServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw LoadCASServiceError.unauthorized(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw LoadCASServiceError.notFound("Not found")
            }
        case let .undocumented(statusCode: statusCode, _):
            throw LoadCASServiceError.unknownError(statusCode)
        }
    }
}
