import Checksum
import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol GraphContentHashing {
    func contentHashes(for graph: TuistCore.Graph) throws -> [TargetNode: String]
}

public final class GraphContentHasher: GraphContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    public init(
        targetContentHasher: TargetContentHashing = TargetContentHasher()
    ) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - GraphContentHashing

    public func contentHashes(for graph: TuistCore.Graph) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]
        let hashableTargets = graph.targets.values.flatMap { (targets: [TargetNode]) -> [TargetNode] in
            targets.compactMap { target in
                if self.isCacheable(target, visited: &visitedNodes) { return target }
                return nil
            }
        }
        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(for: $0)
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Private

    fileprivate func isCacheable(_ target: TargetNode, visited: inout [TargetNode: Bool]) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        let isFramework = target.target.product == .framework
        let noXCTestDependency = !target.dependsOnXCTest
        let allTargetDependenciesAreHasheable = target.targetDependencies.allSatisfy { isCacheable($0, visited: &visited) }
        let cacheable = isFramework && noXCTestDependency && allTargetDependenciesAreHasheable
        visited[target] = cacheable
        return cacheable
    }
}
