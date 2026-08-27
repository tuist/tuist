import Foundation
import Mockable
import OpenAPIRuntime

/// The server's answer to "where should cache traffic go", and how long that
/// answer stays good for.
///
/// `maxAge` comes from the response's `Cache-Control`. The server shortens it
/// while a dedicated instance is being provisioned back, because a stand-in
/// answer stops being right the moment that instance starts serving. It is the
/// server that knows which case this is, so it is the server that sets the
/// interval rather than the client guessing one.
public struct CacheEndpointsResolution: Equatable, Sendable {
    public let endpoints: [String]
    public let maxAge: TimeInterval?

    /// The endpoint that keeps naming this account's cache wherever it is
    /// served from, or `nil` when nothing is answering on one.
    ///
    /// Only the server can say which endpoint this is. `endpoints` is ordered
    /// by proximity to the caller rather than by durability, so position does
    /// not identify it, and recognising it by its shape would put the server's
    /// host template in the client. A server that predates the field omits it,
    /// leaving this nil.
    public let stableEndpoint: String?

    public init(endpoints: [String], maxAge: TimeInterval?, stableEndpoint: String? = nil) {
        self.endpoints = endpoints
        self.maxAge = maxAge
        self.stableEndpoint = stableEndpoint
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

            return seconds
        }

        return nil
    }

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
                // A server that predates the header simply omits it, leaving
                // `maxAge` nil and the client on its own default.
                return CacheEndpointsResolution(
                    endpoints: payload.endpoints,
                    maxAge: Self.maxAge(from: okResponse.headers.cache_hyphen_control),
                    stableEndpoint: payload.stable_endpoint
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
