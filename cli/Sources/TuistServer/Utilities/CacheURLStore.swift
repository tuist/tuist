import Foundation
import Mockable

#if canImport(TuistSupport) && !os(iOS)
    import TuistSupport
#endif

@Mockable
public protocol CacheURLStoring: Sendable {
    func getCacheURL(for serverURL: URL) async throws -> URL
}

public actor CacheURLStore: CacheURLStoring {
    private let cachedValueStore: CachedValueStoring
    private let getCacheEndpointsService: GetCacheEndpointsServicing

    public init(
        cachedValueStore: CachedValueStoring = CachedValueStore(backend: .inSystemProcess),
        getCacheEndpointsService: GetCacheEndpointsServicing = GetCacheEndpointsService()
    ) {
        self.cachedValueStore = cachedValueStore
        self.getCacheEndpointsService = getCacheEndpointsService
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
        #if canImport(TuistSupport)
            Logger.current.debug("Selecting best cache endpoint for \(serverURL.absoluteString)")
        #endif

        let endpoints = try await getCacheEndpointsService.getCacheEndpoints(serverURL: serverURL)

        guard !endpoints.isEmpty else {
            throw CacheURLStoreError.noEndpointsAvailable
        }

        let endpointLatencies = await withTaskGroup(of: (String, TimeInterval?).self) { group in
            for endpoint in endpoints {
                group.addTask {
                    let latency = await self.measureLatency(for: endpoint)
                    return (endpoint, latency)
                }
            }

            var results: [(String, TimeInterval?)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let reachableEndpoints = endpointLatencies.compactMap { endpoint, latency -> (String, TimeInterval)? in
            guard let latency else { return nil }
            return (endpoint, latency)
        }

        #if canImport(TuistSupport)
            for (endpoint, latency) in endpointLatencies {
                if let latency {
                    Logger.current.debug("Endpoint \(endpoint) latency: \(String(format: "%.3f", latency))s")
                } else {
                    Logger.current.debug("Endpoint \(endpoint) is unreachable")
                }
            }
        #endif

        guard !reachableEndpoints.isEmpty else {
            throw CacheURLStoreError.noReachableEndpoints
        }

        let bestEndpoint = reachableEndpoints.min(by: { $0.1 < $1.1 })!

        #if canImport(TuistSupport)
            Logger.current
                .debug(
                    "Selected endpoint \(bestEndpoint.0) with latency \(String(format: "%.3f", bestEndpoint.1))s"
                )
        #endif

        let expirationDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        return (value: bestEndpoint.0, expiresAt: expirationDate)
    }

    private func measureLatency(for endpoint: String) async -> TimeInterval? {
        guard let url = URL(string: endpoint) else {
            return nil
        }

        let healthCheckURL = url.appendingPathComponent("up")
        var request = URLRequest(url: healthCheckURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("0", forHTTPHeaderField: "Expires")

        return await withCheckedContinuation { continuation in
            let delegate = MetricsDelegate(continuation: continuation)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session

            Task {
                _ = try? await session.data(for: request)
            }
        }
    }
}

private final class MetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let latencyContinuation: CheckedContinuation<TimeInterval?, Never>
    var session: URLSession?

    init(continuation: CheckedContinuation<TimeInterval?, Never>) {
        latencyContinuation = continuation
        super.init()
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        defer {
            session?.invalidateAndCancel()
            session = nil
        }

        // Check if the response status is successful
        if let httpResponse = task.response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode)
        {
            latencyContinuation.resume(returning: nil)
            return
        }

        guard let transactionMetrics = metrics.transactionMetrics.first,
              let requestStartDate = transactionMetrics.fetchStartDate,
              let responseEndDate = transactionMetrics.responseEndDate
        else {
            latencyContinuation.resume(returning: nil)
            return
        }

        let latency = responseEndDate.timeIntervalSince(requestStartDate)
        latencyContinuation.resume(returning: latency)
    }
}

enum CacheURLStoreError: LocalizedError {
    case noEndpointsAvailable
    case noReachableEndpoints
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .noEndpointsAvailable:
            return "No cache endpoints are available from the server."
        case .noReachableEndpoints:
            return "None of the cache endpoints are reachable."
        case let .invalidURL(url):
            return "Invalid cache endpoint URL: \(url)."
        }
    }
}
