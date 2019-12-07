import Foundation
import TuistCore

public protocol GraphContentHashing {
    func contentHashes(for graph: Graphing) -> [TargetNode: String]
}

public final class GraphContentHasher: GraphContentHashing {
    public init() {}

    public func contentHashes(for graph: Graphing) -> [TargetNode: String] {
        let hashableTargets = graph.targets.filter { $0.target.product == .framework }
        let hashes = hashableTargets.map { makeContentHash(of: $0) }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    private func makeContentHash(of _: TargetNode) -> String {
        "" // TODO: will be implemented in subsequent PR
    }
}
