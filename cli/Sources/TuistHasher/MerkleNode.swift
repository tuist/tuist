import Foundation

/// Some Tuist features require identifying when a target in the graph has changed.
/// This is something that we achieve by calculating a hash for each target  in the graph
/// that changes when any attribute or dependencies  (e.g. files or other targets) change.
///
/// First versions of the hashing logic did not store information about how the hash was
/// calculated based on the hashes of its dependencies, which made it difficult to understand
/// why a hash for a particular target changed. To solve that, we decided to adopt the
/// [Merkle tree](https://en.wikipedia.org/wiki/Merkle_tree) data structure
/// which stores the hashes while preserving the underlying tree structure.
public struct MerkleNode: Codable, Equatable, Hashable {
    /// The hash of the node.
    public var hash: String

    /// A human-readable identifier
    public var identifier: String

    /// Node children.
    public var children: [MerkleNode]

    public init(hash: String, identifier: String, children: [MerkleNode] = []) {
        self.hash = hash
        self.identifier = identifier
        self.children = children
    }
}
