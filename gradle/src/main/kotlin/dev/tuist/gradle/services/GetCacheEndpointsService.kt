package dev.tuist.gradle.services

import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.api.CacheApi
import dev.tuist.gradle.api.model.CacheEndpoints
import retrofit2.Retrofit
import java.net.URI
import java.util.concurrent.TimeUnit

open class GetCacheEndpointsService(
    private val retrofitProvider: (URI, TokenProvider) -> Retrofit
) {
    /** Convenience constructor for the common case where callers already have a [TuistHttpClients]. */
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retrofitProvider = { url, tokenProvider -> httpClients.authenticatedRetrofit(url, tokenProvider) }
    )

    /**
     * @param timeoutMs bounds the whole call, including any token refresh it triggers; when it
     * runs out the call fails with an [java.io.InterruptedIOException]. `null` keeps the client's
     * own timeouts.
     */
    open fun getCacheEndpoints(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider,
        timeoutMs: Long? = null
    ): CacheEndpoints {
        val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
        val call = api.getCacheEndpoints(accountHandle)
        if (timeoutMs != null) {
            call.timeout().timeout(timeoutMs, TimeUnit.MILLISECONDS)
        }
        val response = call.execute()
        if (!response.isSuccessful) {
            throw RuntimeException(
                response.errorBody()?.string()
                    ?: "Fetching cache endpoints failed with status ${response.code()}."
            )
        }
        return response.body()
            ?: throw RuntimeException("Cache endpoints response was empty.")
    }
}
