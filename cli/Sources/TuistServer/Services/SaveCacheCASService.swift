import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession

@Mockable
public protocol SaveCacheCASServicing: Sendable {
    func saveCacheCAS(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws
}

public enum SaveCacheCASServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case badRequest(String)
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS artifact could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message), let .badRequest(message):
            return message
        case .saveFailed:
            return "The CAS artifact save failed due to an unknown error."
        }
    }
}

public final class SaveCacheCASService: SaveCacheCASServicing {
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

    public func saveCacheCAS(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.saveCacheCAS(
            .init(
                path: .init(id: casId),
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .binary(HTTPBody(data))
            )
        )
        switch response {
        case .noContent:
            return
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw SaveCacheCASServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw SaveCacheCASServiceError.unauthorized(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw SaveCacheCASServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw SaveCacheCASServiceError.unknownError(statusCode)
        }
    }
}
