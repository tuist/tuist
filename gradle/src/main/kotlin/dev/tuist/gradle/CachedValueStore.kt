package dev.tuist.gradle

import java.util.concurrent.CompletableFuture

class CachedValueStore<T>(
    private val isExpired: (T) -> Boolean
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
            val result = compute()
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
}
