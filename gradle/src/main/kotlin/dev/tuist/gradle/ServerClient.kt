package dev.tuist.gradle

import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object ServerClient {

    fun unauthenticated(serverURL: String): Retrofit {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .build()
        return Retrofit.Builder()
            .baseUrl(normalizeBaseUrl(serverURL))
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    fun authenticated(serverURL: String, tokenProvider: TuistTokenProvider): Retrofit {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .addInterceptor(TuistAuthInterceptor(tokenProvider))
            .build()
        return Retrofit.Builder()
            .baseUrl(normalizeBaseUrl(serverURL))
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    private fun normalizeBaseUrl(url: String): String {
        val trimmed = url.trimEnd('/')
        return "$trimmed/"
    }
}
