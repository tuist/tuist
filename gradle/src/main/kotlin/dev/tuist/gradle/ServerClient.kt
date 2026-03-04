package dev.tuist.gradle

import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.net.URI
import java.util.concurrent.TimeUnit

object ServerClient {

    fun unauthenticated(serverURL: URI): Retrofit {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .build()
        return Retrofit.Builder()
            .baseUrl(serverURL.toURL())
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    fun authenticated(serverURL: URI, tokenProvider: TuistTokenProvider): Retrofit {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .addInterceptor(TuistAuthInterceptor(tokenProvider))
            .build()
        return Retrofit.Builder()
            .baseUrl(serverURL.toURL())
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }
}
