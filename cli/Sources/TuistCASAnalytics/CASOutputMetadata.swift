import Foundation
import Mockable

/// Metadata for CAS output operations
public struct CASOutputMetadata: Codable {
    /// Size of the output data in bytes
    public let size: Int

    /// Duration of the output in seconds
    public let duration: TimeInterval

    /// Compressed size of the data in bytes
    public let compressedSize: Int

    public init(size: Int, duration: TimeInterval, compressedSize: Int) {
        self.size = size
        self.duration = duration
        self.compressedSize = compressedSize
    }
}

/// Protocol for storing and retrieving CAS output metadata
@Mockable
public protocol CASOutputMetadataStoring: Sendable {
    /// Store metadata for a CAS output identified by CAS ID
    func storeMetadata(_ metadata: CASOutputMetadata, for casID: String) async throws

    /// Retrieve metadata for a CAS output
    func metadata(for casID: String) async throws -> CASOutputMetadata?
}
