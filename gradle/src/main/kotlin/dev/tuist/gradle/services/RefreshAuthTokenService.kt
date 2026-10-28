package dev.tuist.gradle.services

import dev.tuist.gradle.RetryPolicy
import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.TuistRetry
import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.AuthenticationTokens
import dev.tuist.gradle.api.model.RefreshTokenBody
import retrofit2.Retrofit
import java.io.IOException
import java.io.InterruptedIOException
import java.net.URI
import java.util.concurrent.TimeUnit

/** The server refused the refresh token, so the stored credentials can no longer be used. */
class RefreshTokenRejectedException(status: Int, body: String?) :
    RuntimeException(body ?: "Token refresh failed with status $status.")

/** The server could not be asked to refresh the token, or did not answer; the credentials may still be valid. */
class TokenRefreshUnavailableException(message: String) : IOException(message)

open class RefreshAuthTokenService(
    private val retryPolicy: RetryPolicy = RetryPolicy(),
    private val retrofitProvider: (URI) -> Retrofit
) {
    /** Convenience constructor for the common case where callers already have a [TuistHttpClients]. */
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retryPolicy = httpClients.retryPolicy,
        retrofitProvider = { httpClients.unauthenticatedRetrofit(it) }
    )

    /**
     * The server rotates the refresh token on every refresh, but answers the same refresh token
     * presented again within 60 seconds with the same tokens, so the request is retried like any
     * replay-safe one; a server without that grace window refuses the replay. 400, 401 and 403 fail
     * with [RefreshTokenRejectedException]; any other failure is an [IOException].
     *
     * @param timeoutMs bounds the whole call, including retries; when it runs out the call fails
     * with an [java.io.InterruptedIOException]. `null` keeps the client's own timeouts.
     */
    open fun refreshTokens(serverURL: URI, refreshToken: String, timeoutMs: Long? = null): AuthenticationTokens {
        val api = retrofitProvider(serverURL).create(AuthenticationApi::class.java)
        val deadlineNanos = timeoutMs?.let { System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(it) }
        return TuistRetry.run("Refreshing the Tuist token", replaySafe = true, retryPolicy, deadlineNanos) {
            val call = api.refreshToken(RefreshTokenBody(refreshToken))
            if (deadlineNanos != null) {
                val remainingNanos = deadlineNanos - System.nanoTime()
                if (remainingNanos <= 0) throw InterruptedIOException("Timed out refreshing the Tuist token")
                call.timeout().timeout(remainingNanos, TimeUnit.NANOSECONDS)
            }
            val response = call.execute()
            val status = response.code()
            if (!response.isSuccessful) {
                val body = response.errorBody()?.string()
                if (status in REJECTED_STATUSES) throw RefreshTokenRejectedException(status, body)
                throw TuistRetry.statusFailure(status, response.headers()["Retry-After"]) {
                    TokenRefreshUnavailableException(
                        "The Tuist server could not refresh the token (HTTP $status). It might be temporarily unavailable; try again."
                    )
                }
            }
            response.body()
                ?: throw RuntimeException("Token refresh returned an empty response.")
        }
    }

    private companion object {
        val REJECTED_STATUSES = setOf(400, 401, 403)
    }
}
