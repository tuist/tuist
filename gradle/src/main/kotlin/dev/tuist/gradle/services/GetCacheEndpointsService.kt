package dev.tuist.gradle.services

import dev.tuist.gradle.RetryPolicy
import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.TuistRetry
import dev.tuist.gradle.api.CacheApi
import dev.tuist.gradle.api.model.CacheEndpoints
import retrofit2.Retrofit
import java.io.InterruptedIOException
import java.net.URI
import java.util.concurrent.TimeUnit

open class GetCacheEndpointsService(
    private val retryPolicy: RetryPolicy = RetryPolicy(),
    private val retrofitProvider: (URI, TokenProvider) -> Retrofit
) {
    /** Convenience constructor for the common case where callers already have a [TuistHttpClients]. */
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retryPolicy = httpClients.retryPolicy,
        retrofitProvider = { url, tokenProvider -> httpClients.authenticatedRetrofit(url, tokenProvider) }
    )

    /**
     * Transient failures are retried with [TuistRetry].
     *
     * @param timeoutMs bounds the whole call, including retries and any token refresh it triggers;
     * when it runs out the call fails with an [java.io.InterruptedIOException]. `null` keeps the
     * client's own timeouts.
     */
    open fun getCacheEndpoints(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider,
        timeoutMs: Long? = null
    ): CacheEndpoints {
        val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
        val deadlineNanos = timeoutMs?.let { System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(it) }
        return TuistRetry.run("Fetching cache endpoints", replaySafe = true, retryPolicy, deadlineNanos) {
            val call = api.getCacheEndpoints(accountHandle)
            if (deadlineNanos != null) {
                val remainingNanos = deadlineNanos - System.nanoTime()
                if (remainingNanos <= 0) throw InterruptedIOException("Timed out fetching cache endpoints")
                call.timeout().deadlineNanoTime(deadlineNanos)
            }
            val response = call.execute()
            if (!response.isSuccessful) {
                throw TuistRetry.statusFailure(response.code(), response.headers()["Retry-After"]) {
                    RuntimeException(
                        response.errorBody()?.string()
                            ?: "Fetching cache endpoints failed with status ${response.code()}."
                    )
                }
            }
            response.body()
                ?: throw RuntimeException("Cache endpoints response was empty.")
        }
    }
}
