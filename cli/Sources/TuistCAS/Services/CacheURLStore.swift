import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable
import TuistEnvironment
import TuistLogging
import TuistServer

@Mockable
public protocol CacheURLStoring: Sendable {
    func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL
}

public struct CacheURLStore: CacheURLStoring {
    private let cachedValueStore: CachedValueStoring
    private let getCacheEndpointsService: GetCacheEndpointsServicing
    private let endpointLatencyService: EndpointLatencyServicing
    private let localCache: NSCache<NSString, NSString>
    private let provisioningCacheTTL: TimeInterval

    public init() {
        self.init(
            cachedValueStore: CachedValueStore(backend: .inSystemProcess),
            getCacheEndpointsService: GetCacheEndpointsService(),
            endpointLatencyService: EndpointLatencyService()
        )
    }

    public init(cachedValueStore: CachedValueStoring) {
        self.init(
            cachedValueStore: cachedValueStore,
            getCacheEndpointsService: GetCacheEndpointsService(),
            endpointLatencyService: EndpointLatencyService()
        )
    }

    init(
        cachedValueStore: CachedValueStoring,
        getCacheEndpointsService: GetCacheEndpointsServicing,
        endpointLatencyService: EndpointLatencyServicing,
        provisioningCacheTTL: TimeInterval = CacheURLStore.defaultProvisioningCacheTTL
    ) {
        self.cachedValueStore = cachedValueStore
        self.getCacheEndpointsService = getCacheEndpointsService
        self.endpointLatencyService = endpointLatencyService
        self.provisioningCacheTTL = provisioningCacheTTL
        localCache = NSCache<NSString, NSString>()
    }

    public func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL {
        if let overrideEndpoint = Environment.current.variables["TUIST_CACHE_ENDPOINT"] {
            guard let url = URL(string: overrideEndpoint) else {
                throw CacheURLStoreError.invalidURL(overrideEndpoint)
            }
            Logger.current.debug("Using cache endpoint override: \(overrideEndpoint)")
            return url
        }

        let key =
            "cache_url_\(serverURL.absoluteString)_\(accountHandle ?? "global")_\(currentCacheEndpointKeySuffix())"
        let nsKey = key as NSString

        if let cachedURLString = localCache.object(forKey: nsKey) as? String {
            Logger.current.debug("Returning cached endpoint from local cache: \(cachedURLString)")

            Task {
                await refreshCacheInBackground(for: serverURL, accountHandle: accountHandle, key: key)
            }

            guard let url = URL(string: cachedURLString) else {
                throw CacheURLStoreError.invalidURL(cachedURLString)
            }
            return url
        }

        guard let urlString = try await cachedValueStore.getValue(key: key, computeIfNeeded: {
            try await self.selectBestEndpoint(for: serverURL, accountHandle: accountHandle)
        }) else {
            throw CacheURLStoreError.noEndpointsAvailable
        }

        localCache.setObject(urlString as NSString, forKey: nsKey)

        guard let url = URL(string: urlString) else {
            throw CacheURLStoreError.invalidURL(urlString)
        }

        return url
    }

    private func refreshCacheInBackground(for serverURL: URL, accountHandle: String?, key: String) async {
        Logger.current.debug("Refreshing best cache endpoint in background for \(serverURL.absoluteString)")

        do {
            if let urlString = try await cachedValueStore.getValue(key: key, computeIfNeeded: {
                try await self.selectBestEndpoint(for: serverURL, accountHandle: accountHandle)
            }) {
                localCache.setObject(urlString as NSString, forKey: key as NSString)
            }
        } catch {
            Logger.current.warning("Failed to refresh best cache endpoint for \(serverURL.absoluteString): \(error)")
        }
    }

    private func selectBestEndpoint(for serverURL: URL, accountHandle: String?) async throws
        -> (value: String, expiresAt: Date?)?
    {
        Logger.current.debug("Selecting best cache endpoint for \(serverURL.absoluteString)")

        let resolution = try await getCacheEndpointsService.getCacheEndpoints(
            serverURL: serverURL,
            accountHandle: accountHandle
        )
        let endpoints = resolution.endpoints

        guard !endpoints.isEmpty else {
            throw CacheURLStoreError.noEndpointsAvailable
        }

        if endpoints.count == 1 {
            Logger.current.debug("Only one endpoint available, using it directly: \(endpoints[0])")
            return (value: endpoints[0], expiresAt: expiration(provisioning: resolution.provisioning))
        }

        let endpointLatencies: [(String, TimeInterval?)] = try await endpoints.concurrentMap { endpoint in
            guard let endpointURL = URL(string: endpoint) else {
                Logger.current.warning("Invalid endpoint URL: \(endpoint)")
                return (endpoint, nil)
            }
            let latency = await endpointLatencyService.measureLatency(for: endpointURL)
            return (endpoint, latency)
        }

        let reachableEndpoints = endpointLatencies.compactMap { endpoint, latency -> (String, TimeInterval)? in
            guard let latency else { return nil }
            return (endpoint, latency)
        }

        for (endpoint, latency) in endpointLatencies {
            if let latency {
                Logger.current.debug("Endpoint \(endpoint) latency: \(String(format: "%.3f", latency))s")
            } else {
                Logger.current.debug("Endpoint \(endpoint) is unreachable")
            }
        }

        guard !reachableEndpoints.isEmpty else {
            throw CacheURLStoreError.noReachableEndpoints
        }

        let bestEndpoint = reachableEndpoints.min(by: { $0.1 < $1.1 })!

        Logger.current
            .debug(
                "Selected endpoint \(bestEndpoint.0) with latency \(String(format: "%.3f", bestEndpoint.1))s"
            )

        return (value: bestEndpoint.0, expiresAt: expiration(provisioning: resolution.provisioning))
    }

    /// How long a resolved endpoint stays good for.
    ///
    /// An hour normally, because the answer is stable and the latency race is
    /// not worth repeating. Seconds while the account's own cache instance is
    /// still being provisioned: that answer is a stand-in that stops being
    /// right the moment the instance starts serving, and caching it for the
    /// usual interval would keep a build on the wrong lane long after its own
    /// cache was available.
    private func expiration(provisioning: Bool) -> Date? {
        if provisioning {
            return Date().addingTimeInterval(provisioningCacheTTL)
        }

        return Calendar.current.date(byAdding: .hour, value: 1, to: Date())
    }

    static let defaultProvisioningCacheTTL: TimeInterval = 30

    private func currentCacheEndpointKeySuffix() -> String {
        if ClientFeatureFlags.contains("kura") {
            "kura"
        } else {
            "default"
        }
    }
}

public enum CacheURLStoreError: LocalizedError, Equatable {
    case noEndpointsAvailable
    case noReachableEndpoints
    case invalidURL(String)

    /// Whether the failure is an endpoint that is not serving *yet*, rather than
    /// one that is wrong.
    ///
    /// An account whose cache instance was reclaimed for inactivity has no
    /// endpoint until the server provisions one back, which the very act of
    /// asking for endpoints triggers. The same is true of an instance that is
    /// still rolling out. Both resolve on their own within minutes, and every
    /// per-request caller already degrades to building locally and retries on a
    /// later request, so a long-lived process should carry on rather than refuse
    /// to start over a state that is about to fix itself.
    ///
    /// `invalidURL` is excluded: a malformed endpoint is a misconfiguration that
    /// no amount of waiting corrects, so it stays fatal.
    public var isTransientAbsence: Bool {
        switch self {
        case .noEndpointsAvailable, .noReachableEndpoints:
            true
        case .invalidURL:
            false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .noEndpointsAvailable:
            return "No cache endpoints are available."
        case .noReachableEndpoints:
            return "None of the cache endpoints are reachable."
        case let .invalidURL(url):
            return "Invalid cache endpoint URL: \(url)."
        }
    }
}

extension Array where Element: Sendable {
    fileprivate func concurrentMap<B: Sendable>(
        _ transform: @Sendable @escaping (Element) async throws -> B
    ) async throws -> [B] {
        let tasks = map { element in
            Task {
                try await transform(element)
            }
        }
        var values = [B]()
        for task in tasks {
            try await values.append(task.value)
        }
        return values
    }
}
