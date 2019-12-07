import Foundation

public protocol ContentHashable {
    /// The hash that uniquely identifies the content of the node. Returns nil if the node can't be hashed
    var contentHash: Int? { get }
}
