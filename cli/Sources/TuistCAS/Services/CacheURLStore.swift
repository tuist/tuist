import Foundation
import Mockable
import TuistEnvironment
import TuistServer

@Mockable
public protocol CacheURLStoring: Sendable {
    func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL
}

/// Source compatibility for the pinned cache module. Stable hostname resolution does not poll readiness.
@available(*, deprecated, message: "Cache URLs are derived locally; provisioning readiness is no longer polled.")
public enum CacheProvisioningWait: Equatable, Sendable {
    case none
    case upTo(Duration)

    public static let forInteractiveCommands: CacheProvisioningWait = .upTo(.seconds(30))
}

public struct CacheURLStore: CacheURLStoring {
    public init() {}

    @available(*, deprecated, message: "Use init(); stable cache URLs do not require endpoint discovery or provisioning polling.")
    public init(cachedValueStore _: CachedValueStoring, provisioningWait _: CacheProvisioningWait = .none) {}

    public func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL {
        if let overrideEndpoint = Environment.current.variables["TUIST_CACHE_ENDPOINT"] {
            guard let url = URL(string: overrideEndpoint),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty
            else { throw CacheURLStoreError.invalidURL(overrideEndpoint) }
            return url
        }

        guard serverURL.scheme?.lowercased() == "https",
              serverURL.port == nil || serverURL.port == 443,
              serverURL.path.isEmpty || serverURL.path == "/"
        else { throw CacheURLStoreError.missingEndpointOverride }

        let suffix: String
        switch serverURL.host?.lowercased() {
        case "tuist.dev", "tuist.io": suffix = ""
        case "canary.tuist.dev": suffix = "-canary"
        case "staging.tuist.dev": suffix = "-staging"
        default: throw CacheURLStoreError.missingEndpointOverride
        }

        guard let handle = accountHandle?.lowercased(),
              handle.range(of: "\\A[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?\\z", options: .regularExpression) != nil,
              !handle.hasSuffix("-staging"), !handle.hasSuffix("-canary")
        else { throw CacheURLStoreError.invalidAccountHandle(accountHandle) }

        return URL(string: "https://\(handle)\(suffix).cache.tuist.dev")!
    }
}

public enum CacheURLStoreError: LocalizedError, Equatable {
    case noEndpointsAvailable
    case endpointBeingPrepared
    case noReachableEndpoints
    case invalidURL(String)
    case invalidAccountHandle(String?)
    case missingEndpointOverride
    /// Retained for source compatibility with callers of the legacy resolver.
    case forbidden(String)

    public var isTransientAbsence: Bool {
        switch self {
        case .noEndpointsAvailable, .endpointBeingPrepared, .noReachableEndpoints:
            true
        case .invalidURL, .invalidAccountHandle, .missingEndpointOverride, .forbidden:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .noEndpointsAvailable:
            return "No cache endpoints are available."
        case .endpointBeingPrepared:
            return "The remote cache is being prepared and has no endpoint yet."
        case .noReachableEndpoints:
            return "None of the cache endpoints are reachable."
        case let .invalidURL(url):
            return "Invalid cache endpoint URL: \(url)."
        case let .invalidAccountHandle(handle):
            return "A valid account handle is required to derive the cache endpoint: \(handle ?? "missing")."
        case .missingEndpointOverride:
            return "Set TUIST_CACHE_ENDPOINT to the cache URL for your self-hosted server."
        case let .forbidden(message):
            return message
        }
    }
}
