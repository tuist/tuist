import Foundation

/// Metadata for CAS task operations
public struct CASTaskMetadata: Codable {
    /// Size of the task data in bytes
    public let size: Int
    
    /// Timestamp when the task was recorded
    public let timestamp: Date
    
    public init(size: Int, timestamp: Date = Date()) {
        self.size = size
        self.timestamp = timestamp
    }
}

/// Protocol for storing and retrieving CAS task metadata
public protocol CASTaskMetadataStoring: Sendable {
    /// Store metadata for a CAS task identified by CAS ID
    func storeMetadata(_ metadata: CASTaskMetadata, for casID: String) async throws
    
    /// Retrieve metadata for a CAS task
    func metadata(for casID: String) async throws -> CASTaskMetadata?
}