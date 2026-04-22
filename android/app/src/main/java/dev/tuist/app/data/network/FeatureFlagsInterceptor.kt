package dev.tuist.app.data.network

import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

class FeatureFlagsInterceptor @Inject constructor() : Interceptor {
    private var environmentVariables: Map<String, String> = System.getenv()

    internal constructor(environmentVariables: Map<String, String>) : this() {
        this.environmentVariables = environmentVariables
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val requestBuilder = chain.request().newBuilder()

        FeatureFlagsHeaders.headerValue(environmentVariables)?.let { headerValue ->
            requestBuilder.header(FeatureFlagsHeaders.HEADER_NAME, headerValue)
        }

        return chain.proceed(requestBuilder.build())
    }
}
