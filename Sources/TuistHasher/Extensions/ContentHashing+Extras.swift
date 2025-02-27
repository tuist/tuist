import TuistCore

extension ContentHashing {
    func hash(_ merkleNodes: [MerkleNode]) throws -> String {
        return try hash(merkleNodes.map(\.hash))
    }
}
