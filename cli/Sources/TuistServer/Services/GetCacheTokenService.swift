import Foundation
import Mockable
import OpenAPIRuntime

public struct CacheToken: Equatable, Sendable {
    public let token: String
    public let expiresIn: Int

    public init(token: String, expiresIn: Int) {
        self.token = token
        self.expiresIn = expiresIn
    }
}

@Mockable
public protocol GetCacheTokenServicing: Sendable {
    func getCacheToken(serverURL: URL, projectHandle: String?) async throws -> CacheToken
}

enum GetCacheTokenServiceError: LocalizedError {
    case unauthorized(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .unauthorized(message):
            return message
        case let .unknownError(statusCode):
            return "Failed to obtain a cache token due to an unknown server response of \(statusCode)."
        }
    }
}

public struct GetCacheTokenService: GetCacheTokenServicing {
    public init() {}

    public func getCacheToken(serverURL: URL, projectHandle: String?) async throws -> CacheToken {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getCacheToken(
            .init(query: .init(project_handle: projectHandle))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(cacheToken):
                return CacheToken(token: cacheToken.token, expiresIn: cacheToken.expires_in)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw GetCacheTokenServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheTokenServiceError.unknownError(statusCode)
        }
    }
}
