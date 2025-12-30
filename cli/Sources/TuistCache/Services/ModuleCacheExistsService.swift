import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol ModuleCacheExistsServicing: Sendable {
    func moduleCacheArtifactExists(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Bool
}

public enum ModuleCacheExistsServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Could not check if module cache artifact exists due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message):
            return message
        }
    }
}

public struct ModuleCacheExistsService: ModuleCacheExistsServicing {
    public init() {}

    public func moduleCacheArtifactExists(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Bool {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.moduleCacheArtifactExists(
            .init(
                path: .init(id: hash),
                query: .init(
                    account_handle: accountHandle,
                    project_handle: projectHandle,
                    hash: hash,
                    name: name,
                    cache_category: cacheCategory
                )
            )
        )

        switch response {
        case .noContent:
            return true
        case .notFound:
            return false
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ModuleCacheExistsServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ModuleCacheExistsServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw ModuleCacheExistsServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ModuleCacheExistsServiceError.unknownError(statusCode)
        }
    }
}
