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

    fun getValue(forceRefresh: Boolean = false, compute: () -> Pair<T, Long?>): T {
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
            return future.get()
        }

        try {
            val (value, expiresAtMs) = if (lockFilePath != null) {
                withFileLock { compute() }
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

    private fun withFileLock(action: () -> Pair<T, Long?>): Pair<T, Long?> {
        val lockFile = lockFilePath!!
        lockFile.parentFile.mkdirs()

        if (!Platform.isWindows()) {
            lockFile.createNewFile()
            val fd = posix.open(lockFile.absolutePath, 1) // O_WRONLY
            if (fd < 0) throw IOException("Cannot open refresh lock: ${Native.getLastError()}")
            try {
                // Use flock, like the Swift client; FileChannel.lock uses a different POSIX lock mechanism.
                while (posix.flock(fd, 2) != 0) { // LOCK_EX
                    val error = Native.getLastError()
                    if (error != 4) throw IOException("Cannot acquire refresh lock: $error") // EINTR
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
            var fileLock: FileLock? = null
            while (fileLock == null) {
                try {
                    fileLock = channel.lock()
                } catch (_: OverlappingFileLockException) {
                    Thread.sleep(10)
                }
            }

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

    private companion object {
        val posix: Posix by lazy { Native.load(Platform.C_LIBRARY_NAME, Posix::class.java) }
    }
}
