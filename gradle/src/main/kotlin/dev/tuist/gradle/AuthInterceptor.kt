package dev.tuist.gradle

import okhttp3.Interceptor
import okhttp3.Response

class AuthInterceptor(
    private val tokenProvider: TokenProvider
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        // The call's timeout starts when the call does, just before its interceptors run, and
        // cancelling the call does not interrupt a thread waiting for a token, so the token has
        // to be acquired against the same deadline.
        val callTimeoutNanos = chain.call().timeout().timeoutNanos()
        val deadlineNanos = if (callTimeoutNanos > 0) System.nanoTime() + callTimeoutNanos else null
        val token = tokenProvider.getToken(deadlineNanos = deadlineNanos)
        val request = chain.request().newBuilder()
            .header("Authorization", "Bearer $token")
            .build()
        return chain.proceed(request)
    }
}
