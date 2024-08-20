import Foundation

public struct MerkleNode: Encodable, Equatable, Hashable {
    /// The hash of the node.
    public var hash: String

    /// A human-readable identifier
    public var identifier: String

    /// Nodechildren.
    public var children: [MerkleNode]
}
