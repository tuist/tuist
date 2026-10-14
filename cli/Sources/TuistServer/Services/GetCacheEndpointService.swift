import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

public struct CacheEndpointResolution: Equatable, Sendable {
    public let endpoint: String?
    public let maxAge: TimeInterval?

    public init(endpoint: String?, maxAge: TimeInterval?) {
        self.endpoint = endpoint
        self.maxAge = maxAge
    }
}

@Mockable
public protocol GetCacheEndpointServicing: Sendable {
    func getCacheEndpoint(
        serverURL: URL
    ) async throws -> CacheEndpointResolution
}

public enum GetCacheEndpointServiceError: LocalizedError, Equatable {
    case unknownError(Int)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to retrieve cache endpoints due to an unknown server response of \(statusCode)."
        }
    }
}

extension GetCacheEndpointServiceError: HTTPStatusCodeError {
    public var httpStatusCode: Int {
        switch self {
        case let .unknownError(status): return status
        }
    }
}

public struct GetCacheEndpointService: GetCacheEndpointServicing {
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

    public func getCacheEndpoint(
        serverURL: URL
    ) async throws -> CacheEndpointResolution {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getCacheEndpoint(.init())

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(payload):
                return CacheEndpointResolution(
                    endpoint: payload.endpoint,
                    maxAge: Self.maxAge(from: okResponse.headers.cache_hyphen_control)
                )
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheEndpointServiceError.unknownError(statusCode)
        }
    }
}
