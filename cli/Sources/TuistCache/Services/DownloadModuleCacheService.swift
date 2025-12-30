import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol DownloadModuleCacheServicing: Sendable {
    func downloadModuleCacheArtifact(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Data
}

public enum DownloadModuleCacheServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The module cache artifact could not be downloaded due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .notFound(message),
             let .badRequest(message):
            return message
        }
    }
}

public struct DownloadModuleCacheService: DownloadModuleCacheServicing {
    public init() {}

    public func downloadModuleCacheArtifact(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> Data {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.downloadModuleCacheArtifact(
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
        case let .ok(okResponse):
            switch okResponse.body {
            case let .binary(body):
                return try await Data(collecting: body, upTo: .max)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.forbidden(error.message)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.notFound(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw DownloadModuleCacheServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw DownloadModuleCacheServiceError.unknownError(statusCode)
        }
    }
}
