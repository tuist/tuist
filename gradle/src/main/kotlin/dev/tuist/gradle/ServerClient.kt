package dev.tuist.gradle

import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.net.URI
import java.util.concurrent.TimeUnit

object ServerClient {

    fun unauthenticated(serverURL: URI, proxy: Proxy = Proxy.None): Retrofit {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .applyProxy(proxy)
            .build()
        return Retrofit.Builder()
            .baseUrl(normalizeBaseUrl(serverURL))
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    fun authenticated(serverURL: URI, tokenProvider: TokenProvider, proxy: Proxy = Proxy.None): Retrofit {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .addInterceptor(AuthInterceptor(tokenProvider))
            .applyProxy(proxy)
            .build()
        return Retrofit.Builder()
            .baseUrl(normalizeBaseUrl(serverURL))
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    private fun normalizeBaseUrl(serverURL: URI): String {
        val base = serverURL.resolve("/")
        return base.toASCIIString()
    }

    internal fun OkHttpClient.Builder.applyProxy(proxy: Proxy): OkHttpClient.Builder {
        proxy.resolve()?.let { proxy(it) }
        return this
    }
}
