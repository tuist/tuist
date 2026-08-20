import Foundation
import Mockable
import TuistAlert
import TuistLogging
import TuistServer

@Mockable
public protocol CacheTokenStoring: Sendable {
    /// Returns a token that cache nodes can verify by themselves, exchanging the
    /// caller's credential for one when there is no live token to reuse.
    /// Returns nil when the exchange is unavailable, leaving the caller to send
    /// the credential it already has. Throws when the account's plan bars it
    /// from the cache, which the caller must not paper over by sending the
    /// credential instead.
    func cacheToken(authenticationURL: URL, fullHandle: String?) async throws -> String?
}

/// Exchanges the credential the CLI authenticates with for one a cache node can
/// verify locally, and holds onto it until it is close to expiring.
///
/// The credential used on CI is an opaque string, which a cache node cannot
/// check without asking the server about it, and that question costs a
/// round-trip on every authorization that misses the node's own cache. A cache
/// token carries its grants instead, so the node answers from the token alone.
public actor CacheTokenStore: CacheTokenStoring {
    /// Refresh ahead of expiry so a token does not lapse mid-request.
    private static let expiryMargin: TimeInterval = 60

    /// How long to keep sending the original credential after an exchange fails.
    /// This suppresses attempts rather than making them: a server without the
    /// endpoint fails identically every time, so re-attempting is the failure
    /// mode, not the fix, and the transport already retries what is worth
    /// retrying. Short enough that a server upgraded mid-build is picked up
    /// without restarting the CLI.
    private static let unavailabilityLifetime: TimeInterval = 60

    /// A cache client is built per request, so the exchanged tokens are held here
    /// rather than on the client, which would make every request exchange again.
    public static let shared = CacheTokenStore()

    private let getCacheTokenService: GetCacheTokenServicing
    private let cachedValueStore: CachedValueStoring
    private let now: @Sendable () -> Date

    /// Failures are held here rather than in the value store, which does not
    /// memoize an absent result by design.
    private var unavailableUntil: [String: Date] = [:]

    /// A build makes thousands of cache calls, so the plan is reported once
    /// rather than on every one of them.
    private var warnedFreeTierExhausted = false

    /// Keyed like `unavailableUntil`. Held for the life of the process because
    /// an exhausted plan is not something the next request recovers from, and
    /// forgetting it would resume the credential fallback it exists to stop.
    private var freeTierExhausted: [String: String] = [:]

    public init() {
        self.init(getCacheTokenService: GetCacheTokenService())
    }

    init(
        getCacheTokenService: GetCacheTokenServicing,
        cachedValueStore: CachedValueStoring = CachedValueStore.current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.getCacheTokenService = getCacheTokenService
        self.cachedValueStore = cachedValueStore
        self.now = now
    }

    private func warnFreeTierExhausted(_ message: String) {
        guard !warnedFreeTierExhausted else { return }
        warnedFreeTierExhausted = true
        AlertController.current.warning(.alert("\(message)"))
    }

    public func cacheToken(authenticationURL: URL, fullHandle: String?) async throws -> String? {
        let key = "cache-token-\(authenticationURL.absoluteString)-\(fullHandle ?? "")"

        if let message = freeTierExhausted[key] {
            throw GetCacheTokenServiceError.freeTierExhausted(message)
        }

        if let unavailableUntil = unavailableUntil[key], unavailableUntil > now() {
            return nil
        }

        do {
            // The store holds the token until shortly before it expires and
            // collapses the concurrent callers a build produces onto one
            // exchange, so this only reaches the server when there is nothing
            // live to reuse.
            let token: String? = try await cachedValueStore.getValue(key: key) { [getCacheTokenService] in
                let cacheToken = try await getCacheTokenService.getCacheToken(
                    serverURL: authenticationURL,
                    fullHandle: fullHandle
                )
                return (
                    value: cacheToken.token,
                    expiresAt: Date().addingTimeInterval(
                        max(TimeInterval(cacheToken.expiresIn) - Self.expiryMargin, 0)
                    )
                )
            }
            unavailableUntil[key] = nil
            return token
        } catch {
            if let tokenError = error as? GetCacheTokenServiceError,
               case let .freeTierExhausted(message) = tokenError
            {
                // Not a fallback case. A credential minted before the account
                // crossed the threshold can still carry locally verifiable cache
                // grants, so sending it would keep the cache reachable past the
                // point the server refused to mint for it.
                warnFreeTierExhausted(message)
                freeTierExhausted[key] = message
                throw tokenError
            } else {
                // Cache nodes still accept the original credential, so a server
                // that cannot mint one (an older self-hosted deployment, for
                // example) leaves cache access working exactly as before.
                Logger.current
                    .debug("Using the original credential for cache requests: \(error)")
            }

            unavailableUntil[key] = now().addingTimeInterval(Self.unavailabilityLifetime)
            return nil
        }
    }
}
