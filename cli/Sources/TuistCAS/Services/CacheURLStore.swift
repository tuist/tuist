#if canImport(TuistSupport)
    import Foundation
    import Mockable
    import TuistServer
    import TuistSupport

    @Mockable
    public protocol CacheURLStoring: Sendable {
        func getCacheURL(for serverURL: URL) async throws -> URL
    }

    public struct CacheURLStore: CacheURLStoring {
        private let cachedValueStore: CachedValueStoring
        private let getCacheEndpointsService: GetCacheEndpointsServicing
        private let endpointLatencyService: EndpointLatencyServicing

        public init() {
            self.init(
                cachedValueStore: CachedValueStore(backend: .inSystemProcess),
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
        }

        public func getCacheURL(for serverURL: URL) async throws -> URL {
            let key = "cache_url_\(serverURL.absoluteString)"

            guard let urlString = try await cachedValueStore.getValue(key: key, computeIfNeeded: {
                try await self.selectBestEndpoint(for: serverURL)
            }) else {
                throw CacheURLStoreError.noEndpointsAvailable
            }

            guard let url = URL(string: urlString) else {
                throw CacheURLStoreError.invalidURL(urlString)
            }

            return url
        }

        private func selectBestEndpoint(for serverURL: URL) async throws -> (value: String, expiresAt: Date?)? {
            Logger.current.debug("Selecting best cache endpoint for \(serverURL.absoluteString)")

            let endpoints = try await getCacheEndpointsService.getCacheEndpoints(serverURL: serverURL)

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
