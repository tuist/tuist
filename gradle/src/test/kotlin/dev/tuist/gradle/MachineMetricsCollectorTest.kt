package dev.tuist.gradle

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MachineMetricsCollectorTest {

    private fun createCollector() = MachineMetricsCollector(sampleIntervalMs = 50)

    @Test
    fun `stop returns empty list when no samples collected`() {
        val collector = createCollector()
        val samples = collector.stop()
        assertEquals(emptyList(), samples)
    }

    @Test
    fun `stop returns collected samples after running`() {
        val collector = createCollector()
        collector.start()
        Thread.sleep(150)
        val samples = collector.stop()

        assertTrue(samples.isNotEmpty(), "Expected at least one sample")
    }

    @Test
    fun `samples contain valid timestamps`() {
        val collector = createCollector()
        val beforeStart = System.currentTimeMillis() / 1000.0
        collector.start()
        Thread.sleep(150)
        val samples = collector.stop()
        val afterStop = System.currentTimeMillis() / 1000.0

        assertTrue(samples.isNotEmpty())
        for (sample in samples) {
            assertTrue(sample.timestamp >= beforeStart, "Timestamp should be after start time")
            assertTrue(sample.timestamp <= afterStop, "Timestamp should be before stop time")
        }
    }

    @Test
    fun `samples contain non-negative cpu usage`() {
        val collector = createCollector()
        collector.start()
        Thread.sleep(150)
        val samples = collector.stop()

        assertTrue(samples.isNotEmpty())
        for (sample in samples) {
            assertTrue(sample.cpuUsagePercent >= 0f, "CPU usage should be non-negative")
            assertTrue(sample.cpuUsagePercent <= 100f, "CPU usage should be at most 100%")
        }
    }

    @Test
    fun `samples contain non-negative memory values`() {
        val collector = createCollector()
        collector.start()
        Thread.sleep(150)
        val samples = collector.stop()

        assertTrue(samples.isNotEmpty())
        for (sample in samples) {
            assertTrue(sample.memoryUsedBytes >= 0, "Memory used should be non-negative")
            assertTrue(sample.memoryTotalBytes > 0, "Memory total should be positive")
            assertTrue(
                sample.memoryUsedBytes <= sample.memoryTotalBytes,
                "Memory used should not exceed total"
            )
        }
    }

    @Test
    fun `samples contain non-negative network and disk values`() {
        val collector = createCollector()
        collector.start()
        Thread.sleep(150)
        val samples = collector.stop()

        assertTrue(samples.isNotEmpty())
        for (sample in samples) {
            assertTrue(sample.networkBytesIn >= 0, "Network bytes in should be non-negative")
            assertTrue(sample.networkBytesOut >= 0, "Network bytes out should be non-negative")
            assertTrue(sample.diskBytesRead >= 0, "Disk bytes read should be non-negative")
            assertTrue(sample.diskBytesWritten >= 0, "Disk bytes written should be non-negative")
        }
    }

    @Test
    fun `stop can be called multiple times safely`() {
        val collector = createCollector()
        collector.start()
        Thread.sleep(150)
        val firstResult = collector.stop()
        val secondResult = collector.stop()

        assertTrue(firstResult.isNotEmpty())
        assertEquals(firstResult, secondResult)
    }

    @Test
    fun `start can be called after stop for a new session`() {
        val collector = createCollector()
        collector.start()
        Thread.sleep(150)
        val firstSamples = collector.stop()

        collector.start()
        Thread.sleep(150)
        val secondSamples = collector.stop()

        assertTrue(firstSamples.isNotEmpty())
        assertTrue(secondSamples.size > firstSamples.size, "Second session samples should accumulate on top of first")
    }

    @Test
    fun `multiple samples have increasing timestamps`() {
        val collector = createCollector()
        collector.start()
        Thread.sleep(200)
        val samples = collector.stop()

        assertTrue(samples.size >= 2, "Expected at least 2 samples")
        for (i in 1 until samples.size) {
            assertTrue(
                samples[i].timestamp >= samples[i - 1].timestamp,
                "Timestamps should be non-decreasing"
            )
        }
    }
}
