package dev.tuist.app.data.network

import okhttp3.Interceptor
import okhttp3.Response
import java.util.UUID
import javax.inject.Inject

class RequestIdInterceptor @Inject constructor() : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request().newBuilder()
            .header("X-Request-ID", UUID.randomUUID().toString())
            .build()
        return chain.proceed(request)
    }
}
