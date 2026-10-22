package dev.tuist.gradle

import dev.tuist.gradle.services.CacheFreeTierExhaustedException
import dev.tuist.gradle.services.GetCacheTokenService
import org.slf4j.LoggerFactory
import java.net.URI

/**
 * Exchanges the credential the plugin authenticates with for a token scoped to one project, which
 * cache nodes verify by themselves, and holds onto it until it is close to expiring.
 *
 * The exchanged token also carries the region the server saw the request come from, which cache
 * nodes record with the traffic they serve. Server API calls keep the original credential: the
 * exchanged token is only accepted by cache nodes.
 */
class CacheTokenStore(
    private val serverURL: URI,
    private val fullHandle: String,
    private val tokenProvider: TokenProvider,
    private val getCacheTokenService: GetCacheTokenService,
    private val now: () -> Long = System::currentTimeMillis
) {
    sealed interface Resolution {
        /** When to ask the store again. */
        val validUntilMs: Long
    }

    data class Exchanged(val token: String, override val validUntilMs: Long) : Resolution

    /** The caller sends the credential it already has until [validUntilMs]. */
    data class Unavailable(override val validUntilMs: Long) : Resolution

    private val tokenCache = CachedValueStore<Exchanged>()

    @Volatile
    private var unavailableUntilMs: Long? = null

    /**
     * Held for the rest of the build: an exhausted plan is not something the next request recovers
     * from, and forgetting it would resume the credential fallback it exists to stop.
     */
    @Volatile
    private var freeTierExhausted: CacheFreeTierExhaustedException? = null

    /**
     * Collapses concurrent callers onto one exchange. Throws [CacheFreeTierExhaustedException] when
     * the account's plan bars it from the cache, which the caller must not paper over by sending
     * the credential instead.
     */
    fun resolve(forceRefresh: Boolean = false): Resolution {
        freeTierExhausted?.let { throw it }
        unavailableUntilMs?.let { if (it > now()) return Unavailable(it) }

        return try {
            tokenCache.getValue(forceRefresh) {
                val response = getCacheTokenService.getCacheToken(serverURL, fullHandle, tokenProvider)
                val validUntilMs = now() + maxOf(response.expiresIn * 1000L - EXPIRY_MARGIN_MS, 0)
                Pair(Exchanged(response.token, validUntilMs), validUntilMs)
            }.also { unavailableUntilMs = null }
        } catch (e: CacheFreeTierExhaustedException) {
            synchronized(this) {
                if (freeTierExhausted == null) freeTierExhausted = e
            }
            throw freeTierExhausted ?: e
        } catch (e: Exception) {
            // Cache nodes still accept the original credential, so a server that cannot mint a cache
            // token (an older self-hosted deployment, for example) leaves cache access working.
            logger.debug("Tuist: Using the original credential for cache requests: {}", e.message)
            val until = now() + UNAVAILABILITY_LIFETIME_MS
            unavailableUntilMs = until
            Unavailable(until)
        }
    }

    companion object {
        /** Refresh ahead of expiry so a token does not lapse mid-request. */
        internal const val EXPIRY_MARGIN_MS = 60_000L

        /**
         * How long to keep sending the original credential after an exchange fails. A server without
         * the endpoint fails identically every time, so this suppresses attempts rather than making
         * them, and is short enough that a server upgraded mid-build is picked up.
         */
        internal const val UNAVAILABILITY_LIFETIME_MS = 60_000L

        private val logger = LoggerFactory.getLogger(CacheTokenStore::class.java)
    }
}
