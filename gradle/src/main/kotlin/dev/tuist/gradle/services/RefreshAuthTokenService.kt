package dev.tuist.gradle.services

import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.AuthenticationTokens
import dev.tuist.gradle.api.model.RefreshTokenBody
import retrofit2.Retrofit

class RefreshAuthTokenService(
    private val retrofitProvider: (String) -> Retrofit = { ServerClient.unauthenticated(it) }
) {
    fun refreshTokens(serverURL: String, refreshToken: String): AuthenticationTokens? {
        return try {
            val api = retrofitProvider(serverURL).create(AuthenticationApi::class.java)
            val response = api.refreshToken(RefreshTokenBody(refreshToken)).execute()
            if (response.isSuccessful) response.body() else null
        } catch (_: Exception) {
            null
        }
    }
}
