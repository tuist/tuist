package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class CachedValueStoreTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `cache hit returns stored value without recomputing`() {
        val store = CachedValueStore<String>()
        val computeCount = AtomicInteger(0)

        val compute = {
            computeCount.incrementAndGet()
            Pair("value", null)
        }

        assertEquals("value", store.getValue(compute = compute))
        assertEquals("value", store.getValue(compute = compute))
        assertEquals(1, computeCount.get())
    }

    @Test
    fun `cache expiry triggers recomputation`() {
        val store = CachedValueStore<String>()
        val computeCount = AtomicInteger(0)

        store.getValue {
            computeCount.incrementAndGet()
            Pair("first", System.currentTimeMillis() - 1000)
        }

        val result = store.getValue {
            computeCount.incrementAndGet()
            Pair("second", null)
        }

        assertEquals("second", result)
        assertEquals(2, computeCount.get())
    }

    @Test
    fun `forceRefresh bypasses cache`() {
        val store = CachedValueStore<String>()
        val computeCount = AtomicInteger(0)

        store.getValue {
            computeCount.incrementAndGet()
            Pair("first", null)
        }

        val result = store.getValue(forceRefresh = true) {
            computeCount.incrementAndGet()
            Pair("refreshed", null)
        }

        assertEquals("refreshed", result)
        assertEquals(2, computeCount.get())
    }

    @Test
    fun `concurrent callers deduplicate computation`() {
        val store = CachedValueStore<String>()
        val computeCount = AtomicInteger(0)
        val startLatch = CountDownLatch(1)
        val threads = 5
        val results = Array(threads) { "" }

        val threadList = (0 until threads).map { i ->
            Thread {
                startLatch.await()
                results[i] = store.getValue {
                    computeCount.incrementAndGet()
                    Thread.sleep(50)
                    Pair("shared", null)
                }
            }
        }

        threadList.forEach { it.start() }
        startLatch.countDown()
        threadList.forEach { it.join() }

        assertEquals(1, computeCount.get())
        results.forEach { assertEquals("shared", it) }
    }

    @Test
    fun `compute exception propagates to caller`() {
        val store = CachedValueStore<String>()

        assertFailsWith<IllegalStateException> {
            store.getValue { throw IllegalStateException("compute failed") }
        }
    }

    @Test
    fun `compute exception allows subsequent successful compute`() {
        val store = CachedValueStore<String>()

        assertFailsWith<IllegalStateException> {
            store.getValue { throw IllegalStateException("fail") }
        }

        val result = store.getValue { Pair("recovered", null) }
        assertEquals("recovered", result)
    }

    @Test
    fun `a caller waiting for another caller's computation gives up at its deadline`() {
        val store = CachedValueStore<String>()
        val computing = CountDownLatch(1)
        val release = CountDownLatch(1)
        val owner = Thread {
            store.getValue {
                computing.countDown()
                release.await()
                Pair("value", null)
            }
        }
        owner.start()
        computing.await()

        try {
            val start = System.nanoTime()
            assertFailsWith<TimeoutException> {
                store.getValue(deadlineNanos = start + TimeUnit.MILLISECONDS.toNanos(200)) { Pair("other", null) }
            }
            val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
            assertTrue(elapsedMs < 1_000, "Waited ${elapsedMs}ms with a 200ms deadline")
        } finally {
            release.countDown()
            owner.join()
        }
    }

    @Test
    fun `waiting for a file lock held by another process gives up at the deadline`() {
        val lockFile = File(tempDir, "test.lock")
        val holder = FileLockHolder.start(lockFile)
        val store = CachedValueStore<String>(lockFilePath = lockFile)

        try {
            val start = System.nanoTime()
            assertFailsWith<TimeoutException> {
                store.getValue(deadlineNanos = start + TimeUnit.MILLISECONDS.toNanos(200)) { Pair("value", null) }
            }
            val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
            assertTrue(elapsedMs < 1_000, "Waited ${elapsedMs}ms with a 200ms deadline")
        } finally {
            holder.destroy()
            holder.waitFor()
        }
    }

    @Test
    fun `a file lock released before the deadline is taken`() {
        val lockFile = File(tempDir, "test.lock")
        val holder = FileLockHolder.start(lockFile)
        val store = CachedValueStore<String>(lockFilePath = lockFile)
        Thread {
            Thread.sleep(200)
            holder.destroy()
        }.start()

        val result = store.getValue(deadlineNanos = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)) {
            Pair("value", null)
        }

        assertEquals("value", result)
        holder.waitFor()
    }

    @Test
    fun `works with file lock`() {
        val lockFile = File(tempDir, "test.lock")
        val store = CachedValueStore<String>(lockFilePath = lockFile)

        val result = store.getValue { Pair("locked-value", null) }
        assertEquals("locked-value", result)
    }

    @Test
    fun `file lock creates parent directories`() {
        val lockFile = File(File(tempDir, "nested/dir"), "test.lock")
        val store = CachedValueStore<String>(lockFilePath = lockFile)

        val result = store.getValue { Pair("nested-value", null) }
        assertEquals("nested-value", result)
    }
}
