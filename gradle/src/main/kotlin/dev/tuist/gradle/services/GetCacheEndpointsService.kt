package dev.tuist.gradle.services

import dev.tuist.gradle.CacheTechnology
import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.api.CacheApi
import retrofit2.Retrofit
import java.net.URI

open class GetCacheEndpointsService(
    private val retrofitProvider: (URI, TokenProvider) -> Retrofit
) {
    /** Convenience constructor for the common case where callers already have a [TuistHttpClients]. */
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retrofitProvider = { url, tokenProvider -> httpClients.authenticatedRetrofit(url, tokenProvider) }
    )

    open fun getCacheEndpoints(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider,
        cacheTechnology: CacheTechnology = CacheTechnology.DEFAULT
    ): List<String> {
        val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
        val response = api.getCacheEndpoints(accountHandle, cacheTechnology.queryValue).execute()
        if (!response.isSuccessful) {
            throw RuntimeException(
                response.errorBody()?.string()
                    ?: "Fetching cache endpoints failed with status ${response.code()}."
            )
        }
        return response.body()?.endpoints
            ?: throw RuntimeException("Cache endpoints response was empty.")
    }
}
