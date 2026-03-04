package dev.tuist.gradle

import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.StandardOpenOption
import java.util.concurrent.CompletableFuture

class CachedValueStore<T>(
    private val isExpired: (T) -> Boolean,
    private val lockFilePath: File? = null
) {
    @Volatile
    private var cached: T? = null

    @Volatile
    private var pending: CompletableFuture<T>? = null
    private val lock = Any()

    fun getValue(forceRefresh: Boolean = false, compute: () -> T): T {
        if (!forceRefresh) {
            cached?.let { if (!isExpired(it)) return it }
        }

        val future: CompletableFuture<T>
        val isOwner: Boolean

        synchronized(lock) {
            if (!forceRefresh) {
                cached?.let { if (!isExpired(it)) return it }
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
            val result = if (lockFilePath != null) {
                withFileLock { compute() }
            } else {
                compute()
            }
            cached = result
            future.complete(result)
            return result
        } catch (e: Exception) {
            future.completeExceptionally(e)
            throw e
        } finally {
            synchronized(lock) { pending = null }
        }
    }

    private fun withFileLock(action: () -> T): T {
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
                cached?.let { if (!isExpired(it)) return it }

                return action()
            } finally {
                fileLock.release()
            }
        } finally {
            channel.close()
        }
    }
}
