import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol SaveModuleCacheServicing: Sendable {
    func saveModuleCache(
        _ data: Data,
        fullHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum SaveModuleCacheServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)
    case requestTimeout(String)
    case contentTooLarge(String)
    case internalServerError(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The module cache artifact could not be uploaded due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message),
             let .requestTimeout(message),
             let .contentTooLarge(message),
             let .internalServerError(message):
            return message
        }
    }
}

public final class SaveModuleCacheService: SaveModuleCacheServicing {
    public init() {}

    public func saveModuleCache(
        _ data: Data,
        fullHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.uploadModuleCacheArtifact(
            .init(
                query: .init(
                    project_id: fullHandle,
                    hash: hash,
                    name: name,
                    cache_category: cacheCategory
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
                throw SaveModuleCacheServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw SaveModuleCacheServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw SaveModuleCacheServiceError.badRequest(error.message)
            }
        case let .requestTimeout(timeout):
            switch timeout.body {
            case let .json(error):
                throw SaveModuleCacheServiceError.requestTimeout(error.message)
            }
        case let .contentTooLarge(tooLarge):
            switch tooLarge.body {
            case let .json(error):
                throw SaveModuleCacheServiceError.contentTooLarge(error.message)
            }
        case let .internalServerError(serverError):
            switch serverError.body {
            case let .json(error):
                throw SaveModuleCacheServiceError.internalServerError(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw SaveModuleCacheServiceError.unknownError(statusCode)
        }
    }
}
