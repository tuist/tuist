import Foundation
import Mockable
import TuistEnvironment
import TuistServer

@Mockable
public protocol CacheURLStoring: Sendable {
    func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL
}

/// Source compatibility for the pinned cache module. Stable hostname resolution does not poll readiness.
@available(*, deprecated, message: "Cache requests handle provisioning readiness; URL resolution does not poll.")
public enum CacheProvisioningWait: Equatable, Sendable {
    case none
    case upTo(Duration)

    public static let forInteractiveCommands: CacheProvisioningWait = .upTo(.seconds(30))
}

public struct CacheURLStore: CacheURLStoring {
    private static let configurations = CachedValueStore()
    private let getCacheEndpointService: any GetCacheEndpointServicing
    private let configurationCache: any CachedValueStoring

    public init(
        getCacheEndpointService: any GetCacheEndpointServicing = GetCacheEndpointService(),
        configurationCache: (any CachedValueStoring)? = nil
    ) {
        self.getCacheEndpointService = getCacheEndpointService
        self.configurationCache = configurationCache ?? Self.configurations
    }

    @available(*, deprecated, message: "Use init(configurationCache:); provisioning readiness is handled by cache requests.")
    public init(cachedValueStore: CachedValueStoring, provisioningWait _: CacheProvisioningWait = .none) {
        self.init(configurationCache: cachedValueStore)
    }

    public func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL {
        if let overrideEndpoint = Environment.current.variables["TUIST_CACHE_ENDPOINT"] {
            return try validatedURL(overrideEndpoint)
        }

        let suffix: String?
        if serverURL.scheme?.lowercased() == "https",
           serverURL.port == nil || serverURL.port == 443,
           serverURL.path.isEmpty || serverURL.path == "/"
        {
            switch serverURL.host?.lowercased() {
            case "tuist.dev", "tuist.io": suffix = ""
            case "canary.tuist.dev": suffix = "-canary"
            case "staging.tuist.dev": suffix = "-staging"
            default: suffix = nil
            }
        } else {
            suffix = nil
        }

        guard let suffix else {
            let configuration: CacheEndpointResolution? = try await configurationCache.getValue(
                key: "cache-endpoint:\(serverURL.absoluteString)"
            ) {
                let value = try await getCacheEndpointService.getCacheEndpoint(serverURL: serverURL)
                return (value, Date().addingTimeInterval(max(0, min(value.maxAge ?? 60, 60))))
            }
            guard let endpoint = configuration?.endpoint else { throw CacheURLStoreError.noEndpointsAvailable }
            return try validatedURL(endpoint)
        }

        guard let handle = accountHandle?.lowercased(),
              handle.range(of: "\\A[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?\\z", options: .regularExpression) != nil,
              !handle.hasSuffix("-staging"), !handle.hasSuffix("-canary")
        else { throw CacheURLStoreError.invalidAccountHandle(accountHandle) }

        return URL(string: "https://\(handle)\(suffix).cache.tuist.dev")!
    }

    private func validatedURL(_ endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty
        else { throw CacheURLStoreError.invalidURL(endpoint) }
        return url
    }
}

public enum CacheURLStoreError: LocalizedError, Equatable {
    case invalidURL(String)
    case invalidAccountHandle(String?)
    case noEndpointsAvailable
    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid cache endpoint URL: \(url)."
        case let .invalidAccountHandle(handle):
            return "A valid account handle is required to derive the cache endpoint: \(handle ?? "missing")."
        case .noEndpointsAvailable:
            return "No remote cache endpoint is available."
        }
    }
}
