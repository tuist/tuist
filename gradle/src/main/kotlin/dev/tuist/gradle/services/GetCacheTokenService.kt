package dev.tuist.gradle.services

import com.google.gson.JsonParser
import dev.tuist.gradle.RetryPolicy
import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.TuistRetry
import dev.tuist.gradle.api.CacheApi
import retrofit2.Retrofit
import java.net.URI

data class CacheToken(val token: String, val expiresIn: Long)

/** The account's plan bars it from the cache, so the credential must not be sent instead. */
class CacheFreeTierExhaustedException(message: String) : RuntimeException(message)

open class GetCacheTokenService(
    private val retryPolicy: RetryPolicy = RetryPolicy(),
    private val retrofitProvider: (URI, TokenProvider) -> Retrofit
) {
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retryPolicy = httpClients.retryPolicy,
        retrofitProvider = { url, tokenProvider -> httpClients.authenticatedRetrofit(url, tokenProvider) }
    )

    /**
     * Exchanges the credential [tokenProvider] holds for a cache token scoped to [fullHandle].
     * A 402 fails with [CacheFreeTierExhaustedException]; any other failure is a [RuntimeException]
     * or an [java.io.IOException].
     */
    open fun getCacheToken(serverURL: URI, fullHandle: String, tokenProvider: TokenProvider): CacheToken {
        val api = retrofitProvider(serverURL, tokenProvider).create(CacheApi::class.java)
        return TuistRetry.run("Exchanging the credential for a cache token", replaySafe = true, retryPolicy) {
            val response = api.getCacheToken(fullHandle).execute()
            if (!response.isSuccessful) {
                val body = response.errorBody()?.string()
                if (response.code() == 402) {
                    throw CacheFreeTierExhaustedException(message(body) ?: "The account's plan does not include the remote cache.")
                }
                throw TuistRetry.statusFailure(response.code(), response.headers()["Retry-After"]) {
                    RuntimeException(body ?: "Exchanging the credential for a cache token failed with status ${response.code()}.")
                }
            }
            val json = JsonParser.parseString(response.body()?.string() ?: "").asJsonObject
            CacheToken(json["token"].asString, json["expires_in"].asLong)
        }
    }

    private fun message(body: String?): String? = try {
        body?.let { JsonParser.parseString(it).asJsonObject["message"]?.asString }
    } catch (_: Exception) {
        null
    }
}
