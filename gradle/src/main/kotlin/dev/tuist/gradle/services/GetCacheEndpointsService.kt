package dev.tuist.gradle.services

import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.TuistTokenProvider
import dev.tuist.gradle.api.CacheApi
import retrofit2.Retrofit

class GetCacheEndpointsService(
    private val retrofitProvider: (String, TuistTokenProvider) -> Retrofit =
        { url, tokenProvider -> ServerClient.authenticated(url, tokenProvider) }
) {
    fun getCacheEndpoints(
        serverURL: String,
        accountHandle: String,
        tokenProvider: TuistTokenProvider
    ): List<String>? {
        return try {
            val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
            val response = api.getCacheEndpoints(accountHandle).execute()
            if (response.isSuccessful) response.body()?.endpoints else null
        } catch (_: Exception) {
            null
        }
    }
}
