import Foundation
import Mockable

/// Metadata for CAS output operations
public struct CASOutputMetadata: Codable {
    /// Size of the output data in bytes
    public let size: Int

    /// Duration of the download/upload of the output in seconds
    public let duration: TimeInterval

    /// Compressed size of the data in bytes
    public let compressedSize: Int

    public init(size: Int, duration: TimeInterval, compressedSize: Int) {
        self.size = size
        self.duration = duration
        self.compressedSize = compressedSize
    }
}
