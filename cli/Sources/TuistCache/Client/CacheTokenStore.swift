import Foundation
import Mockable
import TuistLogging
import TuistServer

@Mockable
public protocol CacheTokenStoring: Sendable {
    /// Returns a token that cache nodes can verify by themselves, exchanging the
    /// caller's credential for one when there is no live token to reuse.
    /// Returns nil when the exchange is unavailable, leaving the caller to send
    /// the credential it already has.
    func cacheToken(authenticationURL: URL, projectHandle: String?) async -> String?
}

/// Exchanges the credential the CLI authenticates with for one a cache node can
/// verify locally, and holds onto it until it is close to expiring.
///
/// The credential used on CI is an opaque string, which a cache node cannot
/// check without asking the server about it, and that question costs a
/// round-trip on every authorization that misses the node's own cache. A cache
/// token carries its grants instead, so the node answers from the token alone.
public actor CacheTokenStore: CacheTokenStoring {
    private struct Entry {
        let token: String
        let expiresAt: Date
    }

    /// Refresh ahead of expiry so a token does not lapse mid-request.
    private static let expiryMargin: TimeInterval = 60

    /// How long to keep sending the original credential after an exchange fails.
    /// A server that cannot mint one is the steady state for older self-hosted
    /// deployments, and a build issues enough cache requests that retrying on
    /// each one would add thousands of failing round-trips. Short enough that a
    /// server upgraded mid-build is picked up without restarting the CLI.
    private static let retryCooldown: TimeInterval = 60

    /// A cache client is built per request, so the exchanged tokens are held here
    /// rather than on the client, which would make every request exchange again.
    public static let shared = CacheTokenStore()

    private let getCacheTokenService: GetCacheTokenServicing
    private let now: @Sendable () -> Date
    private var entries: [String: Entry] = [:]
    private var exchanges: [String: Task<CacheToken?, Never>] = [:]
    private var retryAfter: [String: Date] = [:]

    public init() {
        self.init(getCacheTokenService: GetCacheTokenService())
    }

    init(
        getCacheTokenService: GetCacheTokenServicing,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.getCacheTokenService = getCacheTokenService
        self.now = now
    }

    public func cacheToken(authenticationURL: URL, projectHandle: String?) async -> String? {
        let key = "\(authenticationURL.absoluteString)|\(projectHandle ?? "")"

        if let entry = entries[key], entry.expiresAt > now() {
            return entry.token
        }

        if let retryAfter = retryAfter[key], retryAfter > now() {
            return nil
        }

        // A build issues many cache requests at once, so without this they would
        // each start their own exchange while the first one is still in flight.
        if let exchange = exchanges[key] {
            return await exchange.value?.token
        }

        let exchange = Task<CacheToken?, Never> { [getCacheTokenService] in
            do {
                return try await getCacheTokenService.getCacheToken(
                    serverURL: authenticationURL,
                    projectHandle: projectHandle
                )
            } catch {
                // Cache nodes still accept the original credential, so a server
                // that cannot mint one (an older self-hosted deployment, for
                // example) leaves cache access working exactly as before.
                Logger.current
                    .debug("Using the original credential for cache requests: \(error)")
                return nil
            }
        }
        exchanges[key] = exchange

        let cacheToken = await exchange.value
        exchanges[key] = nil

        guard let cacheToken else {
            retryAfter[key] = now().addingTimeInterval(Self.retryCooldown)
            return nil
        }

        retryAfter[key] = nil
        entries[key] = Entry(
            token: cacheToken.token,
            expiresAt: now().addingTimeInterval(
                max(TimeInterval(cacheToken.expiresIn) - Self.expiryMargin, 0)
            )
        )
        return cacheToken.token
    }
}
