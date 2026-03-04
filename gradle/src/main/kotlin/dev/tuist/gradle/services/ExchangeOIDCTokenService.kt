package dev.tuist.gradle.services

import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.api.OidcAuthenticationApi
import dev.tuist.gradle.api.model.OIDCTokenExchangeRequest
import retrofit2.Retrofit

class ExchangeOIDCTokenService(
    private val retrofitProvider: (String) -> Retrofit = { ServerClient.unauthenticated(it) }
) {
    fun exchangeOIDCToken(serverURL: String, oidcToken: String): String? {
        return try {
            val api = retrofitProvider(serverURL).create(OidcAuthenticationApi::class.java)
            val response = api.exchangeOIDCToken(OIDCTokenExchangeRequest(oidcToken)).execute()
            if (response.isSuccessful) response.body()?.accessToken else null
        } catch (_: Exception) {
            null
        }
    }
}
