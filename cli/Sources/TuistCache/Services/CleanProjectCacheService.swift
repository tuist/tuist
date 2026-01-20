import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol CleanProjectCacheServicing: Sendable {
    func cleanProjectCache(
        accountHandle: String,
        projectHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum CleanProjectCacheServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case internalServerError(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The project cache could not be cleaned due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .internalServerError(message):
            return message
        }
    }
}

public struct CleanProjectCacheService: CleanProjectCacheServicing {
    public init() {}

    public func cleanProjectCache(
        accountHandle: String,
        projectHandle: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.cleanProjectCache(
            .init(
                query: .init(
                    account_handle: accountHandle,
                    project_handle: projectHandle
                )
            )
        )

        switch response {
        case .noContent:
            break
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CleanProjectCacheServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw CleanProjectCacheServiceError.forbidden(error.message)
            }
        case let .internalServerError(internalServerError):
            switch internalServerError.body {
            case let .json(error):
                throw CleanProjectCacheServiceError.internalServerError(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CleanProjectCacheServiceError.unknownError(statusCode)
        }
    }
}
