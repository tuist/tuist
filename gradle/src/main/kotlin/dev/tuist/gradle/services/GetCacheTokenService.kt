package dev.tuist.gradle.services

import com.google.gson.Gson
import com.google.gson.JsonObject
import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.api.CacheApi
import dev.tuist.gradle.api.model.CacheToken
import org.gradle.caching.BuildCacheException
import retrofit2.Retrofit
import java.net.URI

/**
 * The account's plan bars it from the cache. A [BuildCacheException], so Gradle reports it once and
 * disables the remote cache for the rest of the build instead of failing the build.
 */
class CacheFreeTierExhaustedException(message: String) : BuildCacheException(message)

open class GetCacheTokenService(
    private val retrofitProvider: (URI, TokenProvider) -> Retrofit
) {
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retrofitProvider = { url, tokenProvider -> httpClients.authenticatedRetrofit(url, tokenProvider) }
    )

    open fun getCacheToken(serverURL: URI, fullHandle: String, tokenProvider: TokenProvider): CacheToken {
        val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
        val response = api.getCacheToken(fullHandle).execute()
        if (!response.isSuccessful) {
            val body = response.errorBody()?.string()
            if (response.code() == HTTP_PAYMENT_REQUIRED) {
                throw CacheFreeTierExhaustedException(
                    errorMessage(body) ?: "The account has exhausted its plan's free tier."
                )
            }
            throw RuntimeException(body ?: "Exchanging a cache token failed with status ${response.code()}.")
        }
        val cacheToken = response.body()
        // Gson leaves fields the response lacks null, whatever their declared type.
        @Suppress("SENSELESS_COMPARISON")
        if (cacheToken == null || cacheToken.token == null || cacheToken.token.isBlank()) {
            throw RuntimeException("The cache token response did not include a token.")
        }
        return cacheToken
    }

    private fun errorMessage(body: String?): String? =
        runCatching { Gson().fromJson(body, JsonObject::class.java)?.get("message")?.asString }
            .getOrNull()
            ?.takeIf(String::isNotBlank)

    private companion object {
        const val HTTP_PAYMENT_REQUIRED = 402
    }
}
