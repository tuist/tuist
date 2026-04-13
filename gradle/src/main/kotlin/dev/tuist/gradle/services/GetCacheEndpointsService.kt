package dev.tuist.gradle.services

import dev.tuist.gradle.Proxy
import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.api.CacheApi
import retrofit2.Retrofit
import java.net.URI

open class GetCacheEndpointsService(
    private val retrofitProvider: (URI, TokenProvider) -> Retrofit =
        { url, tokenProvider -> ServerClient.authenticated(url, tokenProvider) }
) {
    constructor(proxy: Proxy) : this(
        retrofitProvider = { url, tokenProvider -> ServerClient.authenticated(url, tokenProvider, proxy) }
    )

    open fun getCacheEndpoints(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider
    ): List<String> {
        val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
        val response = api.getCacheEndpoints(accountHandle).execute()
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
