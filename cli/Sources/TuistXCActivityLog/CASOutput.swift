import Foundation

public enum CASOperation: Equatable {
    case download
    case upload
}

public struct CASOutput: Equatable {
    public let nodeID: String
    public let checksum: String
    public let size: Int
    public let duration: TimeInterval
    public let compressedSize: Int
    public let operation: CASOperation

    public init(
        nodeID: String,
        checksum: String,
        size: Int,
        duration: TimeInterval,
        compressedSize: Int,
        operation: CASOperation
    ) {
        self.nodeID = nodeID
        self.checksum = checksum
        self.size = size
        self.duration = duration
        self.compressedSize = compressedSize
        self.operation = operation
    }
}
