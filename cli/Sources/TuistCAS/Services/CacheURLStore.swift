#if canImport(TuistSupport)
    import Foundation
    import Mockable
    import TuistServer
    import TuistSupport

    @Mockable
    public protocol CacheURLStoring: Sendable {
        func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL
    }

    public struct CacheURLStore: CacheURLStoring {
        private let cachedValueStore: CachedValueStoring
        private let getCacheEndpointsService: GetCacheEndpointsServicing
        private let endpointLatencyService: EndpointLatencyServicing
        private let localCache: NSCache<NSString, NSString>

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
            endpointLatencyService: EndpointLatencyServicing
        ) {
            self.cachedValueStore = cachedValueStore
            self.getCacheEndpointsService = getCacheEndpointsService
            self.endpointLatencyService = endpointLatencyService
            localCache = NSCache<NSString, NSString>()
        }

        public func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL {
            let key = "cache_url_\(serverURL.absoluteString)_\(accountHandle ?? "global")"
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

            let endpoints = try await getCacheEndpointsService.getCacheEndpoints(
                serverURL: serverURL,
                accountHandle: accountHandle
            )

            guard !endpoints.isEmpty else {
                throw CacheURLStoreError.noEndpointsAvailable
            }

            if endpoints.count == 1 {
                Logger.current.debug("Only one endpoint available, using it directly: \(endpoints[0])")
                let expirationDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
                return (value: endpoints[0], expiresAt: expirationDate)
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

            let expirationDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            return (value: bestEndpoint.0, expiresAt: expirationDate)
        }
    }

    enum CacheURLStoreError: LocalizedError, Equatable {
        case noEndpointsAvailable
        case noReachableEndpoints
        case invalidURL(String)

        var errorDescription: String? {
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
#endif
