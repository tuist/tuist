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
    ) async throws -> [GraphTarget: String]
}

/// `GraphContentHasher`
/// is responsible for computing an hash that uniquely identifies a Tuist `Graph`.
/// It considers only targets that are considered cacheable: frameworks without dependencies on XCTest or on non-cacheable targets
public struct GraphContentHasher: GraphContentHashing {
    private let targetContentHasher: TargetContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
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
    ) async throws -> [GraphTarget: String] {
        let graphTraverser = GraphTraverser(graph: graph)
        var visitedIsHasheableNodes: [GraphTarget: Bool] = [:]
        let hashedTargets: ThreadSafe<[GraphHashedTarget: String]> = ThreadSafe([:])
        let hashedPaths: ThreadSafe<[AbsolutePath: String]> = ThreadSafe([:])

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

        let hashes = try await hashableTargets.serialMap { (target: GraphTarget) async throws -> String in
            let hash = try await targetContentHasher.contentHash(
                for: target,
                hashedTargets: hashedTargets.value,
                hashedPaths: hashedPaths.value,
                additionalStrings: additionalStrings
            )
            hashedPaths.mutate { $0 = hash.hashedPaths }
            hashedTargets.mutate {
                $0[
                    GraphHashedTarget(
                        projectPath: target.path,
                        targetName: target.target.name
                    )
                ] = hash.hash
            }
            return hash.hash
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
