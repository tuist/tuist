package dev.tuist.gradle

import com.google.gson.annotations.SerializedName

data class MachineMetricSample(
    @SerializedName("timestamp") val timestamp: Double,
    @SerializedName("cpu_usage_percent") val cpuUsagePercent: Float,
    @SerializedName("memory_used_bytes") val memoryUsedBytes: Long,
    @SerializedName("memory_total_bytes") val memoryTotalBytes: Long,
    @SerializedName("network_bytes_in") val networkBytesIn: Long,
    @SerializedName("network_bytes_out") val networkBytesOut: Long,
    @SerializedName("disk_bytes_read") val diskBytesRead: Long,
    @SerializedName("disk_bytes_written") val diskBytesWritten: Long
)
