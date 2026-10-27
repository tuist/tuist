import Foundation

public struct MachineMetricSample: Codable, Sendable, Equatable {
    /// Unix timestamp in seconds with millisecond precision.
    public let timestamp: Double
    public let cpuUsagePercent: Double
    public let memoryUsedBytes: Int
    public let memoryTotalBytes: Int
    public let networkBytesIn: Int
    public let networkBytesOut: Int
    public let diskBytesRead: Int
    public let diskBytesWritten: Int

    public init(
        timestamp: Double,
        cpuUsagePercent: Double,
        memoryUsedBytes: Int,
        memoryTotalBytes: Int,
        networkBytesIn: Int,
        networkBytesOut: Int,
        diskBytesRead: Int,
        diskBytesWritten: Int
    ) {
        self.timestamp = timestamp
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.networkBytesIn = networkBytesIn
        self.networkBytesOut = networkBytesOut
        self.diskBytesRead = diskBytesRead
        self.diskBytesWritten = diskBytesWritten
    }
}
