package dev.tuist.gradle

import okhttp3.Interceptor
import okhttp3.Response
import okio.Timeout

class AuthInterceptor(
    private val tokenProvider: TokenProvider
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val token = tokenProvider.getToken(deadlineNanos = deadlineNanos(chain.call().timeout()))
        val request = chain.request().newBuilder()
            .header("Authorization", "Bearer $token")
            .build()
        return chain.proceed(request)
    }

    /**
     * Cancelling the call does not interrupt a thread waiting for a token, so the token is acquired
     * against the call's own bound. A deadline is exact; a relative timeout started with the call,
     * before the interceptors ran, so counting it from now overestimates the time left.
     */
    private fun deadlineNanos(timeout: Timeout): Long? {
        val now = System.nanoTime()
        val timeoutDeadline = timeout.timeoutNanos().takeIf { it > 0 }?.let { now + it }
        val deadline = if (timeout.hasDeadline()) timeout.deadlineNanoTime() else null
        return listOfNotNull(timeoutDeadline, deadline).minOrNull()
    }
}
