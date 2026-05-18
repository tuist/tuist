package dev.tuist.gradle.services

import dev.tuist.gradle.TuistHttpClients
import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.AuthenticationTokens
import dev.tuist.gradle.api.model.RefreshTokenBody
import retrofit2.Retrofit
import java.net.URI

open class RefreshAuthTokenService(
    private val retrofitProvider: (URI) -> Retrofit
) {
    /** Convenience constructor for the common case where callers already have a [TuistHttpClients]. */
    constructor(httpClients: TuistHttpClients = TuistHttpClients()) : this(
        retrofitProvider = { httpClients.unauthenticatedRetrofit(it) }
    )

    open fun refreshTokens(serverURL: URI, refreshToken: String): AuthenticationTokens {
        val api = retrofitProvider(serverURL).create(AuthenticationApi::class.java)
        val response = api.refreshToken(RefreshTokenBody(refreshToken)).execute()
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
