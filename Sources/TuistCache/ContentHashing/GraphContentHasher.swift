import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol GraphContentHashing {
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - filter: If `true`, `TargetNode` is hashed, otherwise it is skipped
    ///     - additionalStrings: Additional strings to be used when hashing graph
    func contentHashes(
        for graph: TuistCore.Graph,
        filter: (TargetNode) -> Bool,
        additionalStrings: [String]
    ) throws -> [TargetNode: String]
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - filter: If `true`, `TargetNode` is hashed, otherwise it is skipped
    ///     - additionalStrings: Additional strings to be used when hashing graph
    func contentHashes(
        for graph: ValueGraph,
        filter: (ValueGraphTarget) -> Bool,
        additionalStrings: [String]
    ) throws -> [ValueGraphTarget: String]
}

public extension GraphContentHashing {
    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - filter: If `true`, `TargetNode` is hashed, otherwise it is skipped
    ///     - additionalStrings: Additional strings to be used when hashing graph
    func contentHashes(
        for graph: TuistCore.Graph,
        filter: (TargetNode) -> Bool = { _ in true },
        additionalStrings: [String] = []
    ) throws -> [TargetNode: String] {
        try contentHashes(
            for: graph,
            filter: filter,
            additionalStrings: additionalStrings
        )
    }

    /// Hashes graph
    /// - Parameters:
    ///     - graph: Graph to hash
    ///     - filter: If `true`, `TargetNode` is hashed, otherwise it is skipped
    ///     - additionalStrings: Additional strings to be used when hashing graph
    func contentHashes(
        for graph: ValueGraph,
        filter: (ValueGraphTarget) -> Bool = { _ in true },
        additionalStrings: [String] = []
    ) throws -> [ValueGraphTarget: String] {
        try contentHashes(
            for: graph,
            filter: filter,
            additionalStrings: additionalStrings
        )
    }
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
        for graph: TuistCore.Graph,
        filter: (TargetNode) -> Bool,
        additionalStrings: [String]
    ) throws -> [TargetNode: String] {
        var visitedNodes: [TargetNode: Bool] = [:]
        let hashableTargets = graph.targets.values.flatMap { (targets: [TargetNode]) -> [TargetNode] in
            targets.compactMap { target in
                if isHashable(
                    target,
                    visited: &visitedNodes,
                    filter: filter
                ) {
                    return target
                } else {
                    return nil
                }
            }
        }
        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(
                for: $0,
                additionalStrings: additionalStrings
            )
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    public func contentHashes(
        for graph: ValueGraph,
        filter: (ValueGraphTarget) -> Bool,
        additionalStrings: [String]
    ) throws -> [ValueGraphTarget: String] {
        let graphTraverser = ValueGraphTraverser(graph: graph)
        var visitedNodes: [ValueGraphTarget: Bool] = [:]
        let hashableTargets = graphTraverser.allTargets().compactMap { target -> ValueGraphTarget? in
            if isHashable(
                target,
                graphTraverser: graphTraverser,
                visited: &visitedNodes,
                filter: filter
            ) {
                return target
            } else {
                return nil
            }
        }
        let hashes = try hashableTargets.map {
            try targetContentHasher.contentHash(
                for: $0,
                additionalStrings: additionalStrings
            )
        }
        return Dictionary(uniqueKeysWithValues: zip(hashableTargets, hashes))
    }

    // MARK: - Private

    private func isHashable(
        _ target: ValueGraphTarget,
        graphTraverser: GraphTraversing,
        visited: inout [ValueGraphTarget: Bool],
        filter: (ValueGraphTarget) -> Bool
    ) -> Bool {
        guard filter(target) else {
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
                $0,
                graphTraverser: graphTraverser,
                visited: &visited,
                filter: filter
            )
        }
        visited[target] = allTargetDependenciesAreHashable
        return allTargetDependenciesAreHashable
    }

    private func isHashable(
        _ target: TargetNode,
        visited: inout [TargetNode: Bool],
        filter: (TargetNode) -> Bool
    ) -> Bool {
        guard filter(target) else {
            visited[target] = false
            return false
        }
        if let visitedValue = visited[target] { return visitedValue }
        let allTargetDependenciesAreHashable = target.targetDependencies
            .allSatisfy {
                isHashable(
                    $0,
                    visited: &visited,
                    filter: filter
                )
            }
        visited[target] = allTargetDependenciesAreHashable
        return allTargetDependenciesAreHashable
    }
}
