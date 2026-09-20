package dev.tuist.gradle

import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.nio.file.StandardOpenOption
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

class CachedValueStore<T>(
    private val lockFilePath: File? = null
) {
    private class CacheEntry<T>(
        val value: T,
        val expiresAtMs: Long?
    ) {
        val isExpired: Boolean
            get() {
                val expiresAt = expiresAtMs ?: return false
                return System.currentTimeMillis() >= expiresAt
            }
    }

    @Volatile
    private var cached: CacheEntry<T>? = null

    @Volatile
    private var pending: CompletableFuture<T>? = null
    private val lock = Any()

    /**
     * @param deadlineNanos a [System.nanoTime] after which waiting for another caller's computation,
     * or for the file lock, gives up with a [TimeoutException]. `null` waits for as long as it takes.
     * It does not bound [compute] itself.
     */
    fun getValue(
        forceRefresh: Boolean = false,
        deadlineNanos: Long? = null,
        compute: () -> Pair<T, Long?>
    ): T {
        if (!forceRefresh) {
            cached?.let { if (!it.isExpired) return it.value }
        }

        val future: CompletableFuture<T>
        val isOwner: Boolean

        synchronized(lock) {
            if (!forceRefresh) {
                cached?.let { if (!it.isExpired) return it.value }
            }

            val existing = pending
            if (existing != null) {
                future = existing
                isOwner = false
            } else {
                future = CompletableFuture<T>()
                pending = future
                isOwner = true
            }
        }

        if (!isOwner) {
            if (deadlineNanos == null) return future.get()
            return future.get(deadlineNanos - System.nanoTime(), TimeUnit.NANOSECONDS)
        }

        try {
            val (value, expiresAtMs) = if (lockFilePath != null) {
                withFileLock(deadlineNanos) { compute() }
            } else {
                compute()
            }
            cached = CacheEntry(value, expiresAtMs)
            future.complete(value)
            return value
        } catch (e: Exception) {
            future.completeExceptionally(e)
            throw e
        } finally {
            synchronized(lock) { pending = null }
        }
    }

    private fun withFileLock(deadlineNanos: Long?, action: () -> Pair<T, Long?>): Pair<T, Long?> {
        val lockFile = lockFilePath!!
        lockFile.parentFile.mkdirs()

        val channel = FileChannel.open(
            lockFile.toPath(),
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE
        )

        try {
            val fileLock = if (deadlineNanos == null) channel.lock() else lockBefore(channel, deadlineNanos)

            try {
                // Double-check in-memory cache after acquiring lock
                cached?.let { if (!it.isExpired) return Pair(it.value, it.expiresAtMs) }

                return action()
            } finally {
                fileLock.release()
            }
        } finally {
            channel.close()
        }
    }

    private fun lockBefore(channel: FileChannel, deadlineNanos: Long): FileLock {
        while (true) {
            // Another process holding the lock makes `tryLock` return null; another channel in
            // this JVM holding it makes it throw.
            val fileLock = try {
                channel.tryLock()
            } catch (_: OverlappingFileLockException) {
                null
            }
            if (fileLock != null) return fileLock

            val remainingNanos = deadlineNanos - System.nanoTime()
            if (remainingNanos <= 0) {
                throw TimeoutException("Timed out waiting for the lock at $lockFilePath")
            }
            Thread.sleep(minOf(LOCK_POLL_INTERVAL_MS, TimeUnit.NANOSECONDS.toMillis(remainingNanos) + 1))
        }
    }

    private companion object {
        const val LOCK_POLL_INTERVAL_MS = 50L
    }
}
