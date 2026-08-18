import Foundation
import Mockable
import OpenAPIRuntime

/// The server's answer to "where should cache traffic go".
///
/// `provisioning` is true when a dedicated instance for the account is not
/// serving yet but is expected to be shortly, so the answer is short-lived and
/// should not be cached for the usual interval.
public struct CacheEndpointsResolution: Equatable, Sendable {
    public let endpoints: [String]
    public let provisioning: Bool

    public init(endpoints: [String], provisioning: Bool) {
        self.endpoints = endpoints
        self.provisioning = provisioning
    }
}

@Mockable
public protocol GetCacheEndpointsServicing: Sendable {
    func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> CacheEndpointsResolution
}

enum GetCacheEndpointsServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to retrieve cache endpoints due to an unknown server response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

public struct GetCacheEndpointsService: GetCacheEndpointsServicing {
    public init() {}

    public func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> CacheEndpointsResolution {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getCacheEndpoints(
            .init(query: .init(account_handle: accountHandle))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(payload):
                // A server that predates the field simply omits it, which
                // reads as not provisioning and keeps the previous behaviour.
                return CacheEndpointsResolution(
                    endpoints: payload.endpoints,
                    provisioning: payload.provisioning ?? false
                )
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetCacheEndpointsServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheEndpointsServiceError.unknownError(statusCode)
        }
    }
}
