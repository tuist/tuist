package dev.tuist.gradle

import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.StandardOpenOption
import java.util.concurrent.CompletableFuture

class CachedValueStore<T>(
    private val isExpired: (T) -> Boolean,
    private val lockFilePath: File? = null,
    private val readFromDisk: (() -> T?)? = null
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

        if (lockFile.exists() && System.currentTimeMillis() - lockFile.lastModified() > 10_000) {
            lockFile.delete()
        }

        val channel = FileChannel.open(
            lockFile.toPath(),
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE
        )
        var fileLock: FileLock? = null
        val deadline = System.currentTimeMillis() + 15_000

        try {
            while (System.currentTimeMillis() < deadline) {
                fileLock = try {
                    channel.tryLock()
                } catch (_: Exception) {
                    null
                }
                if (fileLock != null) break
                Thread.sleep(500)
            }

            if (fileLock == null) {
                throw RuntimeException("Timed out waiting for file lock")
            }

            val diskValue = readFromDisk?.invoke()
            if (diskValue != null && !isExpired(diskValue)) {
                return diskValue
            }

            return action()
        } finally {
            fileLock?.release()
            channel.close()
        }
    }
}
