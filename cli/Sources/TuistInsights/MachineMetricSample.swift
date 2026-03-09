import Foundation

public struct MachineMetricSample: Codable, Sendable {
    public let timestamp: Double
    public let cpuUsagePercent: Double
    public let memoryUsedBytes: Int64
    public let memoryTotalBytes: Int64
    public let networkBytesIn: Int64
    public let networkBytesOut: Int64
    public let diskBytesRead: Int64
    public let diskBytesWritten: Int64

    public init(
        timestamp: Double,
        cpuUsagePercent: Double,
        memoryUsedBytes: Int64,
        memoryTotalBytes: Int64,
        networkBytesIn: Int64,
        networkBytesOut: Int64,
        diskBytesRead: Int64,
        diskBytesWritten: Int64
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
