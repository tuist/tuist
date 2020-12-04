import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol GraphContentHashing {
    func contentHashes(for graph: TuistCore.Graph, cacheOutputType: CacheOutputType) throws -> [TargetNode: String]
}

/// `GraphContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
public final class GraphContentHasher: GraphContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing) {
        let targetContentHasher = TargetContentHasher(contentHasher: contentHasher)
        self.init(contentHasher: contentHasher, targetContentHasher: targetContentHasher)
    }

    public init(contentHasher _: ContentHashing, targetContentHasher: TargetContentHashing) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - GraphContentHashing

    public func contentHashes(for graph: TuistCore.Graph, cacheOutputType: CacheOutputType) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]
        let hashableTargets = graph.targets.values.flatMap { (targets: [TargetNode]) -> [TargetNode] in
            targets.compactMap { target in
                if self.isCacheable(target, visited: &visitedNodes) {
                    return target
                }
                return nil
            }
        }
        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(for: $0,
                                                cacheOutputType: cacheOutputType)
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Private

    fileprivate func isCacheable(_ target: TargetNode, visited: inout [TargetNode: Bool]) -> Bool {
        if let visitedValue = visited[target] { return visitedValue }
        // Ignore bundle targets until they can be properly cached
        if target.target.product == .bundle {
            visited[target] = true
            return true
        }
        
        let isFramework = target.target.product == .framework || target.target.product == .staticFramework
        let noXCTestDependency = !target.dependsOnXCTest
        let allTargetDependenciesAreHasheable = target.targetDependencies.allSatisfy { isCacheable($0, visited: &visited) }
        let cacheable = isFramework && noXCTestDependency && allTargetDependenciesAreHasheable
        visited[target] = cacheable
        return cacheable
    }
}
