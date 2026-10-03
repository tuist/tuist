package dev.tuist.gradle.services

import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.AuthenticationTokens
import dev.tuist.gradle.api.model.RefreshTokenBody
import retrofit2.Retrofit
import java.net.URI
import java.util.concurrent.TimeUnit

open class RefreshAuthTokenService(
    private val retrofitProvider: (URI) -> Retrofit
) {
    /** Convenience constructor for the common case where callers already have a [TuistHttpClients]. */
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retrofitProvider = { httpClients.unauthenticatedRetrofit(it) }
    )

    /**
     * @param timeoutMs bounds the whole call; when it runs out the call fails with an
     * [java.io.InterruptedIOException]. `null` keeps the client's own timeouts.
     */
    open fun refreshTokens(serverURL: URI, refreshToken: String, timeoutMs: Long? = null): AuthenticationTokens {
        val api = retrofitProvider(serverURL).create(AuthenticationApi::class.java)
        val call = api.refreshToken(RefreshTokenBody(refreshToken))
        if (timeoutMs != null) {
            call.timeout().timeout(timeoutMs, TimeUnit.MILLISECONDS)
        }
        val response = call.execute()
        if (!response.isSuccessful) {
            throw RuntimeException(
                response.errorBody()?.string()
                    ?: "Token refresh failed with status ${response.code()}."
            )
        }
        return response.body()
            ?: throw RuntimeException("Token refresh returned an empty response.")
    }
}
