package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

data class RefreshTokenRequest(
    @SerializedName("refresh_token") val refreshToken: String
)

data class AuthenticationTokens(
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("refresh_token") val refreshToken: String
)

data class OIDCTokenRequest(val token: String)

data class OIDCTokenResponse(
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("expires_in") val expiresIn: Int
)

data class CacheEndpointsResponse(val endpoints: List<String>)

class TuistApiClient(private val serverURL: String) {

    private val gson = Gson()
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    fun refreshToken(refreshToken: String): AuthenticationTokens? {
        val body = gson.toJson(RefreshTokenRequest(refreshToken))
            .toRequestBody(jsonMediaType)
        val request = Request.Builder()
            .url("${serverURL.trimEnd('/')}/api/auth/refresh_token")
            .post(body)
            .build()
        return try {
            httpClient.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    response.body?.string()?.let { gson.fromJson(it, AuthenticationTokens::class.java) }
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    fun exchangeOIDCToken(oidcToken: String): String? {
        val body = gson.toJson(OIDCTokenRequest(oidcToken))
            .toRequestBody(jsonMediaType)
        val request = Request.Builder()
            .url("${serverURL.trimEnd('/')}/api/auth/oidc/token")
            .post(body)
            .build()
        return try {
            httpClient.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    response.body?.string()?.let {
                        gson.fromJson(it, OIDCTokenResponse::class.java)?.accessToken
                    }
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    fun getCacheEndpoints(accountHandle: String): List<String>? {
        val request = Request.Builder()
            .url("${serverURL.trimEnd('/')}/api/cache/endpoints?account_handle=$accountHandle")
            .get()
            .build()
        return try {
            httpClient.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    response.body?.string()?.let {
                        gson.fromJson(it, CacheEndpointsResponse::class.java)?.endpoints
                    }
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    fun measureLatency(endpointUrl: String): Long {
        val request = Request.Builder()
            .url("${endpointUrl.trimEnd('/')}/up")
            .get()
            .build()
        val client = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .build()
        val start = System.nanoTime()
        return try {
            client.newCall(request).execute().use {
                TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
            }
        } catch (_: Exception) {
            Long.MAX_VALUE
        }
    }
}
