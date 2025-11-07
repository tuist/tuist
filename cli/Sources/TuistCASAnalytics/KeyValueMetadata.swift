import Foundation
import Mockable

/// Metadata for KeyValue operations (get/put cache keys)
public struct KeyValueMetadata: Codable {
    /// Duration of the get/put operation in milliseconds
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = duration
    }
}
