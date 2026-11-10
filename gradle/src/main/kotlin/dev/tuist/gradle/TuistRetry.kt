package dev.tuist.gradle

import org.gradle.api.logging.Logging
import java.io.EOFException
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.NoRouteToHostException
import java.net.SocketException
import java.util.concurrent.TimeUnit
import kotlin.math.pow
import kotlin.random.Random

/**
 * How often and how long requests to Tuist are retried while the server is briefly unavailable,
 * for example while its pods are replaced: 4 attempts, waiting about 250 ms, 1 s and 2 s between
 * them (each jittered by up to 20% and capped at [maxBackoffMs]). A `Retry-After` the server sends
 * replaces the computed wait, capped at [maxBackoffMs].
 */
class RetryPolicy(
    val maxAttempts: Int = 4,
    val initialBackoffMs: Long = 250,
    val maxBackoffMs: Long = 2_000,
    val backoffMultiplier: Double = 4.0,
    internal val sleeper: (Long) -> Unit = { Thread.sleep(it) },
    internal val jitter: () -> Double = { Random.nextDouble() }
) {
    internal fun delayMs(retry: Int, retryAfterMs: Long?): Long {
        if (retryAfterMs != null) return retryAfterMs.coerceIn(0, maxBackoffMs)
        val base = minOf(initialBackoffMs * backoffMultiplier.pow(retry - 1), maxBackoffMs.toDouble())
        return (base * (0.8 + 0.4 * jitter())).toLong().coerceIn(0, maxBackoffMs)
    }
}

/**
 * Thrown by an attempt that received a status worth retrying (502, 503, 504). Once attempts run
 * out, or the status is not retried, [failure] is thrown instead.
 */
class RetryableStatusException(
    val status: Int,
    val retryAfterMs: Long?,
    val failure: Exception
) : IOException("HTTP $status", failure)

/** Recorded on a failure a retry loop gave up on, so an enclosing loop does not replay it. */
internal class RetriesStopped : Exception("Tuist stopped retrying this request") {
    override fun fillInStackTrace(): Throwable = this
}

internal object TuistRetry {
    val RETRYABLE_STATUSES = setOf(502, 503, 504)

    private const val SERVICE_UNAVAILABLE = 503
    private val logger = Logging.getLogger(TuistRetry::class.java)

    /**
     * Runs [attempt] until it succeeds, it fails with something that is not transient, or the
     * policy's attempts run out, rethrowing the last failure.
     *
     * Connection failures before the request reached the server (refused, no route) and 503 are
     * always retried. With [replaySafe], connections dropped while waiting for
     * the response (reset, closed, unexpected end of stream) and 502/504 are retried too: use it
     * only when the server tolerates receiving the request twice. Timeouts, cancellations and
     * interruptions are never retried: a host that does not answer would multiply the wait.
     */
    fun <T> run(
        description: String,
        replaySafe: Boolean,
        policy: RetryPolicy,
        deadlineNanos: Long? = null,
        attempt: () -> T
    ): T {
        var attemptNumber = 1
        while (true) {
            try {
                return attempt()
            } catch (e: Exception) {
                val retryableStatus = e as? RetryableStatusException
                val failure = retryableStatus?.failure ?: e
                if (attemptNumber >= policy.maxAttempts || !isRetryable(e, replaySafe)) throw stopped(failure)

                val delayMs = policy.delayMs(attemptNumber, retryableStatus?.retryAfterMs)
                if (deadlineNanos != null && System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(delayMs) >= deadlineNanos) {
                    throw stopped(failure)
                }
                logger.info(
                    "Tuist: {} failed ({}); retrying in {} ms (attempt {} of {})",
                    description, reason(e), delayMs, attemptNumber + 1, policy.maxAttempts
                )
                try {
                    policy.sleeper(delayMs)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw stopped(failure)
                }
                attemptNumber++
            }
        }
    }

    /** The exception for a retryable [status], or null when [status] is not retried. */
    fun statusFailure(status: Int, retryAfter: String?, failure: () -> Exception): Exception =
        if (status in RETRYABLE_STATUSES) {
            RetryableStatusException(status, parseRetryAfterMs(retryAfter), failure())
        } else {
            failure()
        }

    fun statusFailure(connection: HttpURLConnection, status: Int, failure: () -> Exception): Exception =
        statusFailure(status, connection.getHeaderField("Retry-After"), failure)

    internal fun parseRetryAfterMs(value: String?): Long? =
        value?.trim()?.toLongOrNull()?.takeIf { it >= 0 }?.let { TimeUnit.SECONDS.toMillis(it) }

    internal fun isRetryable(error: Throwable, replaySafe: Boolean): Boolean {
        if (Thread.currentThread().isInterrupted) return false
        if (error is RetryableStatusException) return replaySafe || error.status == SERVICE_UNAVAILABLE
        val chain = causalChain(error)
        if (chain.any { cause -> cause.suppressed.any { it is RetriesStopped } }) return false
        for (cause in chain) {
            when {
                isConnectFailure(cause) -> return true
                cause is InterruptedIOException || cause is InterruptedException -> return false
            }
        }
        return replaySafe && chain.any(::isDroppedConnection)
    }

    private fun stopped(failure: Exception): Exception {
        if (isRetryable(failure, replaySafe = true)) failure.addSuppressed(RetriesStopped())
        return failure
    }

    private fun isConnectFailure(error: Throwable): Boolean =
        error is ConnectException || error is NoRouteToHostException

    private fun isDroppedConnection(error: Throwable): Boolean =
        error is SocketException ||
            error is EOFException ||
            (error is IOException && error.message?.contains("unexpected end of stream", ignoreCase = true) == true)

    private fun reason(error: Throwable): String {
        if (error is RetryableStatusException) return "HTTP ${error.status}"
        val cause = causalChain(error).firstOrNull { isConnectFailure(it) || isDroppedConnection(it) } ?: error
        return "${cause.javaClass.simpleName}: ${cause.message ?: "(no message)"}"
    }

    private fun causalChain(error: Throwable): List<Throwable> =
        generateSequence(error) { it.cause.takeIf { cause -> cause !== it } }.take(16).toList()
}
