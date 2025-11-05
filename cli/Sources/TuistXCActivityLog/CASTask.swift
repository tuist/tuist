import Foundation

public struct CASTask: Equatable {
    public let nodeID: String
    public let checksum: String
    public let size: Int
    public let startedAt: Date
    public let finishedAt: Date
    public let duration: TimeInterval
    public let compressedSize: Int

    public init(
        nodeID: String,
        checksum: String,
        size: Int,
        startedAt: Date,
        finishedAt: Date,
        duration: TimeInterval,
        compressedSize: Int
    ) {
        self.nodeID = nodeID
        self.checksum = checksum
        self.size = size
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.duration = duration
        self.compressedSize = compressedSize
    }
}
