import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol GraphContentHashing {
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - filter: If `true`, `TargetNode` is hashed, otherwise it is skipped
    ///     - additionalStrings: Additional strings to be used when hashing graph
    func contentHashes(
        for graph: Graph,
        include: @escaping (GraphTarget) -> Bool,
        additionalStrings: [String]
    ) throws -> [GraphTarget: String]
}

/// `GraphContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
public final class GraphContentHasher: GraphContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    public convenience init(contentHasher: ContentHashing) {
        let targetContentHasher = TargetContentHasher(contentHasher: contentHasher)
        self.init(targetContentHasher: targetContentHasher)
    }

    public init(targetContentHasher: TargetContentHashing) {
        self.targetContentHasher = targetContentHasher
    }

    // MARK: - GraphContentHashing

    public func contentHashes(
        for graph: Graph,
        include: (GraphTarget) -> Bool,
        additionalStrings: [String]
    ) throws -> [GraphTarget: String] {
        let graphTraverser = GraphTraverser(graph: graph)
        var visitedIsHasheableNodes: [GraphTarget: Bool] = [:]
        var hashedTargets: [GraphHashedTarget: String] = [:]
        var hashedPaths: [AbsolutePath: String] = [:]

        let sortedCacheableTargets = try graphTraverser.allTargetsTopologicalSorted()

        let hashableTargets = sortedCacheableTargets.compactMap { target -> GraphTarget? in
            if isHashable(
                target,
                graphTraverser: graphTraverser,
                visited: &visitedIsHasheableNodes,
                include: include
            ) {
                return target
            } else {
                return nil
            }
        }

        let hashes = try hashableTargets.map { (target: GraphTarget) -> String in
            let hash = try targetContentHasher.contentHash(
                for: target,
                hashedTargets: &hashedTargets,
                hashedPaths: &hashedPaths,
                additionalStrings: additionalStrings
            )
            hashedTargets[
                GraphHashedTarget(
                    projectPath: target.path,
                    targetName: target.target.name
                )
            ] = hash
            return hash
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Private

    private func isHashable(
        _ target: GraphTarget,
        graphTraverser: GraphTraversing,
        visited: inout [GraphTarget: Bool],
        include: (GraphTarget) -> Bool
    ) -> Bool {
        guard include(target) else {
            visited[target] = false
            return false
        }
        if let visitedValue = visited[target] { return visitedValue }
        let allTargetDependenciesAreHashable = graphTraverser.directTargetDependencies(
            path: target.path,
            name: target.target.name
        )
        .allSatisfy {
            isHashable(
                $0.graphTarget,
                graphTraverser: graphTraverser,
                visited: &visited,
                include: include
            )
        }
        visited[target] = allTargetDependenciesAreHashable
        return allTargetDependenciesAreHashable
    }
}
