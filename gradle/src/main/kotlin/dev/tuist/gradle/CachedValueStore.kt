package dev.tuist.gradle

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Platform
import java.io.File
import java.io.IOException
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
        } catch (e: Throwable) {
            future.completeExceptionally(e)
            throw e
        } finally {
            synchronized(lock) { pending = null }
        }
    }

    private fun withFileLock(deadlineNanos: Long?, action: () -> Pair<T, Long?>): Pair<T, Long?> {
        val lockFile = lockFilePath!!
        lockFile.parentFile.mkdirs()

        if (!Platform.isWindows()) {
            lockFile.createNewFile()
            val fd = posix.open(lockFile.absolutePath, 1) // O_WRONLY
            if (fd < 0) throw IOException("Cannot open refresh lock: ${Native.getLastError()}")
            try {
                // Use flock, like the Swift client; FileChannel.lock uses a different POSIX lock mechanism.
                while (posix.flock(fd, 6) != 0) { // LOCK_EX | LOCK_NB
                    val error = Native.getLastError()
                    if (error != 4 && error != 11 && error != 35) { // EINTR, Linux/macOS EWOULDBLOCK
                        throw IOException("Cannot acquire refresh lock: $error")
                    }
                    waitForLock(deadlineNanos)
                }
                cached?.let { if (!it.isExpired) return Pair(it.value, it.expiresAtMs) }
                return action()
            } finally {
                posix.close(fd)
            }
        }

        val channel = FileChannel.open(
            lockFile.toPath(),
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE
        )

        try {
            val fileLock = lockBefore(channel, deadlineNanos)

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

    private interface Posix : Library {
        fun open(path: String, flags: Int): Int
        fun flock(fd: Int, operation: Int): Int
        fun close(fd: Int): Int
    }

    private fun lockBefore(channel: FileChannel, deadlineNanos: Long?): FileLock {
        while (true) {
            // Another process holding the lock makes `tryLock` return null; another channel in
            // this JVM holding it makes it throw.
            val fileLock = try {
                channel.tryLock()
            } catch (_: OverlappingFileLockException) {
                null
            }
            if (fileLock != null) return fileLock

            waitForLock(deadlineNanos)
        }
    }

    private fun waitForLock(deadlineNanos: Long?) {
        val waitMs = if (deadlineNanos == null) LOCK_POLL_INTERVAL_MS else {
            val remainingNanos = deadlineNanos - System.nanoTime()
            if (remainingNanos <= 0) {
                throw TimeoutException("Timed out waiting for the lock at $lockFilePath")
            }
            minOf(LOCK_POLL_INTERVAL_MS, TimeUnit.NANOSECONDS.toMillis(remainingNanos) + 1)
        }
        Thread.sleep(waitMs)
    }

    private companion object {
        val posix: Posix by lazy { Native.load(Platform.C_LIBRARY_NAME, Posix::class.java) }
        const val LOCK_POLL_INTERVAL_MS = 50L
    }
}
