package dev.tuist.gradle.services

import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.AuthenticationTokens
import dev.tuist.gradle.api.model.RefreshTokenBody
import retrofit2.Retrofit
import java.net.URI

class RefreshAuthTokenServiceError(message: String) : RuntimeException(message)

open class RefreshAuthTokenService(
    private val retrofitProvider: (URI) -> Retrofit = { ServerClient.unauthenticated(it) }
) {
    open fun refreshTokens(serverURL: URI, refreshToken: String): AuthenticationTokens {
        val api = retrofitProvider(serverURL).create(AuthenticationApi::class.java)
        val response = api.refreshToken(RefreshTokenBody(refreshToken)).execute()
        if (response.isSuccessful) {
            return response.body()
                ?: throw RefreshAuthTokenServiceError("Token refresh returned an empty response.")
        } else {
            val errorMessage = response.errorBody()?.string()
                ?: "Token refresh failed with status ${response.code()}."
            throw RefreshAuthTokenServiceError(errorMessage)
        }
    }
}
