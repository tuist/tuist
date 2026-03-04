package dev.tuist.gradle

import java.io.File
import java.nio.channels.FileChannel
import java.nio.file.StandardOpenOption
import java.util.concurrent.CompletableFuture

class CachedValueStore<T>(
    private val lockFilePath: File? = null
) {
    private data class CacheEntry<T>(
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
        } catch (e: Exception) {
            future.completeExceptionally(e)
            throw e
        } finally {
            synchronized(lock) { pending = null }
        }
    }

    private fun withFileLock(action: () -> Pair<T, Long?>): Pair<T, Long?> {
        val lockFile = lockFilePath!!
        lockFile.parentFile.mkdirs()

        val channel = FileChannel.open(
            lockFile.toPath(),
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE
        )

        try {
            val fileLock = channel.lock()

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
}
