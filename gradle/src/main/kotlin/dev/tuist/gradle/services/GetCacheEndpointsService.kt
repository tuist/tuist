package dev.tuist.gradle.services

import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.api.CacheApi
import retrofit2.Retrofit
import java.net.URI

class GetCacheEndpointsServiceError(message: String) : RuntimeException(message)

open class GetCacheEndpointsService(
    private val retrofitProvider: (URI, TokenProvider) -> Retrofit =
        { url, tokenProvider -> ServerClient.authenticated(url, tokenProvider) }
) {
    open fun getCacheEndpoints(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider
    ): List<String> {
        val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
        val response = api.getCacheEndpoints(accountHandle).execute()
        if (response.isSuccessful) {
            return response.body()?.endpoints
                ?: throw GetCacheEndpointsServiceError("Cache endpoints response was empty.")
        } else {
            val errorMessage = response.errorBody()?.string()
                ?: "Fetching cache endpoints failed with status ${response.code()}."
            throw GetCacheEndpointsServiceError(errorMessage)
        }
    }
}
