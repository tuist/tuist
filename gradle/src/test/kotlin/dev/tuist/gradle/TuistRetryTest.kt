package dev.tuist.gradle

import org.gradle.caching.BuildCacheException
import org.junit.jupiter.api.Test
import java.io.EOFException
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertSame
import kotlin.test.assertTrue

class TuistRetryTest {

    private val sleeps = mutableListOf<Long>()
    private val policy = RetryPolicy(sleeper = { sleeps += it }, jitter = { 0.5 })

    private fun <T> run(replaySafe: Boolean, failures: List<Exception>, result: T): Pair<T, Int> {
        var attempts = 0
        val value = TuistRetry.run("Test request", replaySafe, policy) {
            attempts++
            failures.getOrNull(attempts - 1)?.let { throw it }
            result
        }
        return value to attempts
    }

    private fun status(code: Int, retryAfter: String? = null) =
        TuistRetry.statusFailure(code, retryAfter) { IOException("HTTP $code") }

    @Test
    fun `waits 250 ms, 1 s and 2 s between four attempts`() {
        val error = IOException("HTTP 503")
        val failure = assertFailsWith<IOException> {
            run(replaySafe = true, failures = List(4) { RetryableStatusException(503, null, error) }, result = Unit)
        }

        assertSame(error, failure)
        assertEquals(listOf(250L, 1_000L, 2_000L), sleeps)
    }

    @Test
    fun `jitter stays within 20 percent and never exceeds the cap`() {
        val low = RetryPolicy(jitter = { 0.0 })
        val high = RetryPolicy(jitter = { 1.0 })

        assertEquals(listOf(200L, 800L, 1_600L), (1..3).map { low.delayMs(it, null) })
        assertEquals(listOf(300L, 1_200L, 2_000L), (1..3).map { high.delayMs(it, null) })
    }

    @Test
    fun `a Retry-After replaces the backoff and is capped at 2 s`() {
        run(replaySafe = true, failures = listOf(status(503, "1"), status(503, "120")), result = Unit)

        assertEquals(listOf(1_000L, 2_000L), sleeps)
    }

    @Test
    fun `replay-safe requests retry connection failures and gateway statuses`() {
        val failures = listOf(
            ConnectException("Connection refused"),
            NoRouteToHostException("No route to host"),
            SocketException("Connection reset")
        )
        for (failure in failures) {
            assertEquals("ok" to 2, run(replaySafe = true, failures = listOf(failure), result = "ok"), failure.toString())
        }
        for (failure in listOf(EOFException(), IOException("unexpected end of stream on http://localhost/..."))) {
            assertEquals("ok" to 2, run(replaySafe = true, failures = listOf(failure), result = "ok"), failure.toString())
        }
        for (code in listOf(502, 503, 504)) {
            assertEquals("ok" to 2, run(replaySafe = true, failures = listOf(status(code)), result = "ok"), "HTTP $code")
        }
    }

    @Test
    fun `wrapped connection failures are retried`() {
        val failure = BuildCacheException("Tuist load failed", ConnectException("Connection refused"))

        assertEquals("ok" to 2, run(replaySafe = true, failures = listOf(failure), result = "ok"))
    }

    @Test
    fun `requests that are not replay-safe retry only failures before the server saw them and 503`() {
        for (failure in listOf(ConnectException("refused"), status(503))) {
            assertEquals("ok" to 2, run(replaySafe = false, failures = listOf(failure), result = "ok"), failure.toString())
        }
        for (failure in listOf(SocketException("Connection reset"), EOFException(), status(502), status(504))) {
            var attempts = 0
            assertFailsWith<IOException>(failure.toString()) {
                TuistRetry.run("Test request", replaySafe = false, policy) {
                    attempts++
                    throw failure
                }
            }
            assertEquals(1, attempts, failure.toString())
        }
    }

    @Test
    fun `timeouts, cancellations and other statuses are never retried`() {
        val failures = listOf(
            SocketTimeoutException("Read timed out"),
            SocketTimeoutException("Connect timed out"),
            InterruptedIOException("timeout").apply { initCause(SocketException("Socket closed")) },
            IOException("Canceled"),
            status(500),
            status(429),
            IllegalStateException("bug")
        )
        for (failure in failures) {
            var attempts = 0
            assertFailsWith<Exception> {
                TuistRetry.run("Test request", replaySafe = true, policy) {
                    attempts++
                    throw failure
                }
            }
            assertEquals(1, attempts, failure.toString())
        }
    }

    @Test
    fun `an interrupted thread does not retry`() {
        var attempts = 0
        try {
            Thread.currentThread().interrupt()
            assertFailsWith<ConnectException> {
                TuistRetry.run("Test request", replaySafe = true, policy) {
                    attempts++
                    throw ConnectException("refused")
                }
            }
        } finally {
            Thread.interrupted()
        }
        assertEquals(1, attempts)
    }

    @Test
    fun `a failure an inner request gave up on is not replayed by an enclosing retry`() {
        var innerAttempts = 0
        var outerAttempts = 0
        assertFailsWith<SocketException> {
            TuistRetry.run("Outer request", replaySafe = true, policy) {
                outerAttempts++
                TuistRetry.run("Inner request", replaySafe = false, policy) {
                    innerAttempts++
                    throw SocketException("Connection reset")
                }
            }
        }

        assertEquals(1, innerAttempts)
        assertEquals(1, outerAttempts)
    }

    @Test
    fun `an exhausted inner retry is not multiplied by an enclosing retry`() {
        var innerAttempts = 0
        val failure = assertFailsWith<ConnectException> {
            TuistRetry.run("Outer request", replaySafe = true, policy) {
                TuistRetry.run("Inner request", replaySafe = true, policy) {
                    innerAttempts++
                    throw ConnectException("refused")
                }
            }
        }

        assertEquals(4, innerAttempts)
        assertTrue(failure.suppressed.any { it is RetriesStopped })
    }
}
