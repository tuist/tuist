package dev.tuist.gradle

import org.gradle.internal.cc.impl.InputTrackingState
import java.io.File
import java.lang.management.ManagementFactory

class MachineMetricsCollector(
    private val sampleIntervalMs: Long = 1000,
    private val inputTrackingState: InputTrackingState? = null,
    private val currentTimeMillis: () -> Long = System::currentTimeMillis
) {
    private class Reading(
        val timestamp: Double,
        val networkBytesIn: Long,
        val networkBytesOut: Long,
        val diskBytesRead: Long,
        val diskBytesWritten: Long
    )

    private val samples = mutableListOf<MachineMetricSample>()
    @Volatile private var running = false
    private var thread: Thread? = null
    private val osMXBean = ManagementFactory.getOperatingSystemMXBean()

    private var previousReading: Reading? = null
    private var readingBeforePrevious: Reading? = null

    @Synchronized
    fun start() {
        if (running) return
        running = true
        previousReading = null
        readingBeforePrevious = null
        collectSample()

        thread = Thread({
            while (running) {
                try {
                    Thread.sleep(sampleIntervalMs)
                    if (!running) break
                    collectSample()
                } catch (e: InterruptedException) {
                    break
                }
            }
        }, "tuist-machine-metrics-collector")
        thread?.isDaemon = true
        thread?.start()
    }

    @Synchronized
    fun stop(): List<MachineMetricSample> {
        if (!running) return synchronized(samples) { samples.toList() }
        running = false
        thread?.interrupt()
        thread?.join(2000)
        if (thread?.isAlive != true) collectSample(isFinal = true)
        return synchronized(samples) { samples.toList() }
    }

    private fun collectSample(isFinal: Boolean = false) {
        val timestamp = currentTimeMillis() / 1000.0
        // A final reading shortly after a periodic one replaces it and measures rates from the
        // reading before, so monitoring reaches the stop time without a tiny rate interval.
        val replacesPrevious = isFinal && readingBeforePrevious != null &&
            previousReading?.let { (timestamp - it.timestamp) * 1000 < 200 } == true
        val baseline = if (replacesPrevious) readingBeforePrevious else previousReading
        val elapsedSeconds = baseline?.let { timestamp - it.timestamp } ?: 0.0

        val cpuUsage = getCpuUsage()
        val memory = getMemoryInfo()
        val network = withoutInputTracking { readNetworkBytes() }
        val disk = withoutInputTracking { readDiskBytes() }

        fun rate(current: Long, previous: Long?): Long =
            if (previous != null && elapsedSeconds > 0) (maxOf(0L, current - previous) / elapsedSeconds).toLong() else 0L

        val sample = MachineMetricSample(
            timestamp = timestamp,
            cpuUsagePercent = cpuUsage,
            memoryUsedBytes = memory.first,
            memoryTotalBytes = memory.second,
            networkBytesIn = rate(network.first, baseline?.networkBytesIn),
            networkBytesOut = rate(network.second, baseline?.networkBytesOut),
            diskBytesRead = rate(disk.first, baseline?.diskBytesRead),
            diskBytesWritten = rate(disk.second, baseline?.diskBytesWritten)
        )
        readingBeforePrevious = baseline
        previousReading = Reading(timestamp, network.first, network.second, disk.first, disk.second)

        synchronized(samples) {
            if (replacesPrevious) samples.removeAt(samples.lastIndex)
            samples.add(sample)
        }
    }

    private fun <T> withoutInputTracking(action: () -> T): T {
        inputTrackingState?.disableForCurrentThread()
        return try {
            action()
        } finally {
            inputTrackingState?.restoreForCurrentThread()
        }
    }

    private fun getCpuUsage(): Float {
        return try {
            val sunBean = osMXBean as? com.sun.management.OperatingSystemMXBean
            val cpuLoad = sunBean?.cpuLoad ?: sunBean?.systemLoadAverage?.let { it / (osMXBean.availableProcessors) } ?: 0.0
            if (cpuLoad < 0 || cpuLoad.isNaN()) return 0f
            (cpuLoad * 100).toFloat().coerceIn(0f, 100f)
        } catch (e: Exception) {
            0f
        }
    }

    private fun getMemoryInfo(): Pair<Long, Long> {
        return try {
            val sunBean = osMXBean as? com.sun.management.OperatingSystemMXBean
            if (sunBean != null) {
                val total = sunBean.totalMemorySize
                val free = sunBean.freeMemorySize
                Pair(total - free, total)
            } else {
                val runtime = Runtime.getRuntime()
                Pair(runtime.totalMemory() - runtime.freeMemory(), runtime.maxMemory())
            }
        } catch (e: Exception) {
            Pair(0L, 0L)
        }
    }

    // -- Network --

    private fun readNetworkBytes(): Pair<Long, Long> {
        return try {
            val procNetDev = File("/proc/net/dev")
            when {
                procNetDev.exists() -> readNetworkBytesLinux(procNetDev)
                MacOSSystemMetrics.isAvailable -> MacOSSystemMetrics.readNetworkBytes()
                // Unsupported platform (e.g. Windows)
                else -> Pair(0L, 0L)
            }
        } catch (e: Exception) {
            Pair(0L, 0L)
        }
    }

    private fun readNetworkBytesLinux(procNetDev: File): Pair<Long, Long> {
        var totalIn = 0L
        var totalOut = 0L
        procNetDev.readLines().drop(2).forEach { line ->
            val parts = line.trim().split("\\s+".toRegex())
            if (parts.size >= 10) {
                totalIn += parts[1].toLongOrNull() ?: 0L
                totalOut += parts[9].toLongOrNull() ?: 0L
            }
        }
        return Pair(totalIn, totalOut)
    }

    // -- Disk --

    private fun readDiskBytes(): Pair<Long, Long> {
        return try {
            val diskStats = File("/proc/diskstats")
            when {
                diskStats.exists() -> readDiskBytesLinux(diskStats)
                MacOSSystemMetrics.isAvailable -> MacOSSystemMetrics.readDiskBytes()
                // Unsupported platform (e.g. Windows)
                else -> Pair(0L, 0L)
            }
        } catch (e: Exception) {
            Pair(0L, 0L)
        }
    }

    private fun readDiskBytesLinux(diskStats: File): Pair<Long, Long> {
        var totalRead = 0L
        var totalWritten = 0L
        diskStats.readLines().forEach { line ->
            val parts = line.trim().split("\\s+".toRegex())
            if (parts.size >= 14) {
                totalRead += (parts[5].toLongOrNull() ?: 0L) * 512
                totalWritten += (parts[9].toLongOrNull() ?: 0L) * 512
            }
        }
        return Pair(totalRead, totalWritten)
    }
}
