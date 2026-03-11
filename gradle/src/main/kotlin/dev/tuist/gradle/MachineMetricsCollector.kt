package dev.tuist.gradle

import java.io.File
import java.lang.management.ManagementFactory

class MachineMetricsCollector(
    private val sampleIntervalMs: Long = 1000
) {
    private val samples = mutableListOf<MachineMetricSample>()
    @Volatile private var running = false
    private var thread: Thread? = null
    private val osMXBean = ManagementFactory.getOperatingSystemMXBean()

    private var previousNetworkBytesIn = 0L
    private var previousNetworkBytesOut = 0L
    private var previousDiskBytesRead = 0L
    private var previousDiskBytesWritten = 0L

    fun start() {
        running = true
        val initialNetwork = readNetworkBytes()
        previousNetworkBytesIn = initialNetwork.first
        previousNetworkBytesOut = initialNetwork.second
        val initialDisk = readDiskBytes()
        previousDiskBytesRead = initialDisk.first
        previousDiskBytesWritten = initialDisk.second

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

    fun stop(): List<MachineMetricSample> {
        running = false
        thread?.interrupt()
        thread?.join(2000)
        return synchronized(samples) { samples.toList() }
    }

    private fun collectSample() {
        val timestamp = System.currentTimeMillis() / 1000.0

        val cpuUsage = getCpuUsage()
        val memory = getMemoryInfo()
        val network = readNetworkBytes()
        val disk = readDiskBytes()

        val networkIn = maxOf(0L, network.first - previousNetworkBytesIn)
        val networkOut = maxOf(0L, network.second - previousNetworkBytesOut)
        val diskRead = maxOf(0L, disk.first - previousDiskBytesRead)
        val diskWritten = maxOf(0L, disk.second - previousDiskBytesWritten)

        previousNetworkBytesIn = network.first
        previousNetworkBytesOut = network.second
        previousDiskBytesRead = disk.first
        previousDiskBytesWritten = disk.second

        val sample = MachineMetricSample(
            timestamp = timestamp,
            cpuUsagePercent = cpuUsage,
            memoryUsedBytes = memory.first,
            memoryTotalBytes = memory.second,
            networkBytesIn = networkIn,
            networkBytesOut = networkOut,
            diskBytesRead = diskRead,
            diskBytesWritten = diskWritten
        )

        synchronized(samples) {
            samples.add(sample)
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
