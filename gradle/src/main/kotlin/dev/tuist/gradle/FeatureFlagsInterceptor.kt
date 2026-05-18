package dev.tuist.gradle

import okhttp3.Interceptor
import okhttp3.Response

class FeatureFlagsInterceptor(
    private val environmentVariables: Map<String, String> = System.getenv()
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val requestBuilder = chain.request().newBuilder()

        FeatureFlagsHeaders.headerValue(environmentVariables)?.let { headerValue ->
            requestBuilder.header(FeatureFlagsHeaders.HEADER_NAME, headerValue)
        }

        return chain.proceed(requestBuilder.build())
    }
}
