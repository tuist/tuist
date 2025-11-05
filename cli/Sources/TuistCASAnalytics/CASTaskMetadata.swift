import Foundation

/// Metadata for CAS task operations
public struct CASTaskMetadata: Codable {
    /// Size of the task data in bytes
    public let size: Int
    
    /// When the task started
    public let startedAt: Date
    
    /// When the task finished
    public let finishedAt: Date
    
    /// Duration of the task in seconds
    public let duration: TimeInterval
    
    /// Compressed size of the data in bytes
    public let compressedSize: Int
    
    public init(size: Int, startedAt: Date, finishedAt: Date, duration: TimeInterval, compressedSize: Int) {
        self.size = size
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.duration = duration
        self.compressedSize = compressedSize
    }
}

/// Protocol for storing and retrieving CAS task metadata
public protocol CASTaskMetadataStoring: Sendable {
    /// Store metadata for a CAS task identified by CAS ID
    func storeMetadata(_ metadata: CASTaskMetadata, for casID: String) async throws
    
    /// Retrieve metadata for a CAS task
    func metadata(for casID: String) async throws -> CASTaskMetadata?
}