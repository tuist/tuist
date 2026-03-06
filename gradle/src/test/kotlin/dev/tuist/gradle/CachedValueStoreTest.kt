package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

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
