import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public struct CacheEndpointsResolution: Equatable, Sendable {
    public let endpoints: [String]
    public let maxAge: TimeInterval?
    public let deriveStableHostname: Bool

    public init(endpoints: [String], maxAge: TimeInterval?, deriveStableHostname: Bool = false) {
        self.endpoints = endpoints
        self.maxAge = maxAge
        self.deriveStableHostname = deriveStableHostname
    }
}

@Mockable
public protocol GetCacheEndpointsServicing: Sendable {
    func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> CacheEndpointsResolution
}

public enum GetCacheEndpointsServiceError: LocalizedError, Equatable {
    case unknownError(Int)
    case forbidden(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to retrieve cache endpoints due to an unknown server response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

extension GetCacheEndpointsServiceError: HTTPStatusCodeError {
    public var httpStatusCode: Int {
        switch self {
        case let .unknownError(status): return status
        case .forbidden: return 403
        }
    }
}

public struct GetCacheEndpointsService: GetCacheEndpointsServicing {
    public init() {}

    /// Reads `max-age` out of a `Cache-Control` value, ignoring the other
    /// directives, which say nothing about how long this answer is good for.
    static func maxAge(from cacheControl: String?) -> TimeInterval? {
        guard let cacheControl else { return nil }

        for directive in cacheControl.split(separator: ",") {
            let parts = directive.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "max-age",
                  let seconds = TimeInterval(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }

            return seconds.isFinite && seconds >= 0 ? seconds : nil
        }

        return nil
    }

    public func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> CacheEndpointsResolution {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getCacheEndpoints(
            .init(query: .init(configuration_only: true, account_handle: accountHandle))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(payload):
                return CacheEndpointsResolution(
                    endpoints: payload.endpoints,
                    maxAge: Self.maxAge(from: okResponse.headers.cache_hyphen_control),
                    deriveStableHostname: payload.derive_stable_hostname ?? false
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
