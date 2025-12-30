import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol SaveCacheCASServicing: Sendable {
    func saveCacheCAS(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum SaveCacheCASServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case badRequest(String)
    case requestTimeout(String)
    case contentTooLarge(String)
    case internalServerError(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS artifact could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .notFound(message),
             let .badRequest(message),
             let .requestTimeout(message),
             let .contentTooLarge(message),
             let .internalServerError(message):
            return message
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
        let response = try await client.saveCASArtifact(
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
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw SaveCacheCASServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw SaveCacheCASServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw SaveCacheCASServiceError.badRequest(error.message)
            }
        case let .requestTimeout(timeout):
            switch timeout.body {
            case let .json(error):
                throw SaveCacheCASServiceError.requestTimeout(error.message)
            }
        case let .contentTooLarge(tooLarge):
            switch tooLarge.body {
            case let .json(error):
                throw SaveCacheCASServiceError.contentTooLarge(error.message)
            }
        case let .internalServerError(serverError):
            switch serverError.body {
            case let .json(error):
                throw SaveCacheCASServiceError.internalServerError(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw SaveCacheCASServiceError.unknownError(statusCode)
        }
    }
}
