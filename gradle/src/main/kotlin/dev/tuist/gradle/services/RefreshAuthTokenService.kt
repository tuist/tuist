package dev.tuist.gradle.services

import dev.tuist.gradle.Proxy
import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.AuthenticationTokens
import dev.tuist.gradle.api.model.RefreshTokenBody
import retrofit2.Retrofit
import java.net.URI

open class RefreshAuthTokenService(
    private val retrofitProvider: (URI) -> Retrofit = { ServerClient.unauthenticated(it) }
) {
    constructor(proxy: Proxy) : this(
        retrofitProvider = { ServerClient.unauthenticated(it, proxy) }
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
