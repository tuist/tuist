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
    /// Every endpoint the account is currently served from, unranked.
    func getCacheEndpoints(for serverURL: URL, accountHandle: String?) async throws -> [URL]
}

/// Whether resolving an endpoint waits for a cache instance the server is preparing.
public enum CacheProvisioningWait: Equatable, Sendable {
    /// Answer with what the server has now. For callers on a request path, or restarted until
    /// they succeed, where blocking would stall the work that is waiting on them.
    case none
    /// Ask the server again until an endpoint serves or `Duration` of wall-clock time has passed.
    case upTo(Duration)

    /// For commands a person or a CI job runs. An account's instance is prepared on demand,
    /// typically in seconds, so such a run is better served by waiting for it than by falling
    /// back to the local cache straight away.
    public static let forInteractiveCommands: CacheProvisioningWait = .upTo(.seconds(30))
}

public struct CacheURLStore: CacheURLStoring {
    private let cachedValueStore: CachedValueStoring
    private let getCacheEndpointsService: GetCacheEndpointsServicing
    private let endpointLatencyService: EndpointLatencyServicing
    private let provisioningWait: CacheProvisioningWait
    private let provisioningPollInterval: Duration
    private let localCache: NSCache<NSString, NSString>

    public init(provisioningWait: CacheProvisioningWait = .none) {
        self.init(
            cachedValueStore: CachedValueStore(backend: .inSystemProcess),
            provisioningWait: provisioningWait
        )
    }

    public init(
        cachedValueStore: CachedValueStoring,
        provisioningWait: CacheProvisioningWait = .none
    ) {
        self.init(
            cachedValueStore: cachedValueStore,
            getCacheEndpointsService: GetCacheEndpointsService(),
            endpointLatencyService: EndpointLatencyService(),
            provisioningWait: provisioningWait
        )
    }

    init(
        cachedValueStore: CachedValueStoring,
        getCacheEndpointsService: GetCacheEndpointsServicing,
        endpointLatencyService: EndpointLatencyServicing,
        provisioningWait: CacheProvisioningWait = .none,
        provisioningPollInterval: Duration = .milliseconds(250)
    ) {
        self.cachedValueStore = cachedValueStore
        self.getCacheEndpointsService = getCacheEndpointsService
        self.endpointLatencyService = endpointLatencyService
        self.provisioningWait = provisioningWait
        self.provisioningPollInterval = provisioningPollInterval
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

        // Not the `cache_url_` names earlier releases stored their answers under:
        // those can still hold endpoints the server no longer routes clients to.
        let key = "cache_endpoint_\(serverURL.absoluteString)_\(accountHandle ?? "global")"
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

    public func getCacheEndpoints(for serverURL: URL, accountHandle: String?) async throws -> [URL] {
        if Environment.current.variables["TUIST_CACHE_ENDPOINT"] != nil {
            return [try await getCacheURL(for: serverURL, accountHandle: accountHandle)]
        }

        return try await Self.fetchCacheEndpoints(
            service: getCacheEndpointsService,
            serverURL: serverURL,
            accountHandle: accountHandle
        )
        .endpoints
        .map { endpoint in
            guard let url = URL(string: endpoint) else { throw CacheURLStoreError.invalidURL(endpoint) }
            return url
        }
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

        let resolution = try await resolutionWaitingForProvisioning(serverURL: serverURL, accountHandle: accountHandle)
        let endpoints = resolution.endpoints

        guard !endpoints.isEmpty else {
            throw resolution.provisioning ? CacheURLStoreError.endpointBeingPrepared : CacheURLStoreError.noEndpointsAvailable
        }

        if endpoints.count == 1 {
            Logger.current.debug("Only one endpoint available, using it directly: \(endpoints[0])")
            return (value: endpoints[0], expiresAt: expiration(maxAge: resolution.maxAge))
        }

        let endpointLatencies: [(String, TimeInterval?)] = try await endpoints.concurrentMap { endpoint in
            guard let endpointURL = URL(string: endpoint) else {
                Logger.current.warning("Invalid endpoint URL: \(endpoint)")
                return (endpoint, nil)
            }
            let latency = await measureLatency(for: endpointURL)
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

        return (value: bestEndpoint.0, expiresAt: expiration(maxAge: resolution.maxAge))
    }

    /// The server's answer, asked again every `provisioningPollInterval` while it has no endpoint
    /// and is preparing an instance, until the `provisioningWait` budget has elapsed.
    ///
    /// The budget is wall-clock time from the first answer: requests count against it as much as
    /// the pauses between them, and neither a pause nor a request is allowed to run past it, so a
    /// slow server cannot stretch the wait before the caller falls back.
    private func resolutionWaitingForProvisioning(serverURL: URL, accountHandle: String?) async throws
        -> CacheEndpointsResolution
    {
        var resolution = try await Self.fetchCacheEndpoints(
            service: getCacheEndpointsService,
            serverURL: serverURL,
            accountHandle: accountHandle
        )
        guard Self.isBeingPrepared(resolution), case let .upTo(budget) = provisioningWait,
              budget > .zero, provisioningPollInterval > .zero
        else { return resolution }

        Logger.current.notice(
            "The remote cache is being prepared. Waiting up to \(budget.components.seconds) seconds for it to be ready."
        )
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        while Self.isBeingPrepared(resolution) {
            let untilDeadline = clock.now.duration(to: deadline)
            guard untilDeadline > .zero else { break }
            try await Task.sleep(for: min(provisioningPollInterval, untilDeadline))

            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero,
                  let next = try await fetchResolution(serverURL: serverURL, accountHandle: accountHandle, within: remaining)
            else { break }
            resolution = next
        }
        return resolution
    }

    private static func fetchCacheEndpoints(
        service: GetCacheEndpointsServicing,
        serverURL: URL,
        accountHandle: String?
    ) async throws -> CacheEndpointsResolution {
        do {
            return try await service.getCacheEndpoints(serverURL: serverURL, accountHandle: accountHandle)
        } catch let GetCacheEndpointsServiceError.forbidden(message) {
            throw CacheURLStoreError.forbidden(message)
        }
    }

    private static func isBeingPrepared(_ resolution: CacheEndpointsResolution) -> Bool {
        resolution.endpoints.isEmpty && resolution.provisioning
    }

    /// The server's answer, or `nil` when it does not arrive within `timeout`.
    ///
    /// The request and the timer run in tasks of their own, so giving up on the request does not
    /// wait for it to end. A task group would: cancelling the request does not end every wait it
    /// can be in, such as the one for a token refresh another request started.
    private func fetchResolution(serverURL: URL, accountHandle: String?, within timeout: Duration) async throws
        -> CacheEndpointsResolution?
    {
        let getCacheEndpointsService = getCacheEndpointsService
        let (outcomes, continuation) = AsyncThrowingStream<CacheEndpointsResolution?, any Error>.makeStream()
        let request = Task {
            do {
                let resolution = try await Self.fetchCacheEndpoints(
                    service: getCacheEndpointsService,
                    serverURL: serverURL,
                    accountHandle: accountHandle
                )
                continuation.yield(resolution)
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let timer = Task {
            try await Task.sleep(for: timeout)
            continuation.yield(nil)
        }
        defer {
            request.cancel()
            timer.cancel()
        }

        for try await outcome in outcomes {
            return outcome
        }
        try Task.checkCancellation()
        return nil
    }

    /// A failed probe is retried once before the endpoint counts as unreachable,
    /// so a single bad response from a serving endpoint does not hand the
    /// selection to a farther one.
    private func measureLatency(for endpointURL: URL) async -> TimeInterval? {
        if let latency = await endpointLatencyService.measureLatency(for: endpointURL) {
            return latency
        }
        return await endpointLatencyService.measureLatency(for: endpointURL)
    }

    /// How long a resolved endpoint stays good for.
    ///
    /// The server says, through `Cache-Control`: a long interval while a
    /// dedicated instance is serving, seconds while one is being provisioned
    /// back, since that answer is a stand-in that stops being right the moment
    /// the instance starts serving. Falling back to an hour covers a server
    /// that sends no directive.
    private func expiration(maxAge: TimeInterval?) -> Date? {
        guard let maxAge else {
            return Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        }

        return Date().addingTimeInterval(maxAge)
    }
}

public enum CacheURLStoreError: LocalizedError, Equatable {
    case noEndpointsAvailable
    case endpointBeingPrepared
    case noReachableEndpoints
    case invalidURL(String)
    /// The server refused to name the account's endpoints to the caller, for example because the
    /// logged-in user is not a member of the account.
    case forbidden(String)

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
    /// `invalidURL` and `forbidden` are excluded: a malformed endpoint and an
    /// account the caller does not belong to are misconfigurations that no amount
    /// of waiting corrects.
    public var isTransientAbsence: Bool {
        switch self {
        case .noEndpointsAvailable, .endpointBeingPrepared, .noReachableEndpoints:
            true
        case .invalidURL, .forbidden:
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
        case let .forbidden(message):
            return message
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
